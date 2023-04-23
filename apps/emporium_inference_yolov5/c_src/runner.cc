#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <iostream>
#include <memory>
#include <random>
#include <string>

#include <opencv2/dnn/dnn.hpp>
#include <torch/script.h>
#include <torch/torch.h>

#include "ei.h"

#ifdef HAVE_CUDA
  #include <c10/cuda/CUDAStream.h>
#endif

// The Runner is a C node (hidden Node using Erlang Distribution) which connects to a Parent Node
// on startup. It accepts the following Environment Variables:
// 
// - `NODE_NAME`: The name of the Erlang node which this C node connects to 
// - `NODE_COOKIE`: The cookie to use when connecting to the parent node
// - `MODEL_TYPE`: (Reserved) either `TorchScript` or `TensorRT`
// - `MODEL_PATH`: The path of the model to load
// - `READY_MODULE`: The name of the Module to send a ready message via RPC
// - `READY_FUNCTION`: The function in the Module to send a ready message via RPC
// - `READY_VALUE`: Unique string which identifies the worker; part of the ready message
// - `LOGGER_LEVEL`: Level of the Erlang logger (per-message logging will be disabled above debug)
// 
// Upon startup, the following operations take place:
// 
// 1. Erlang Distribution is set up and the local C node connected to the parent (identified via
//    `NODE_NAME` and `NODE_COOKIE`). The C node is set up as a hidden node to the parent.
// 
// 2. The TorchScript model is loaded (path identified via `MODEL_PATH`) to be prepared for use.
// 
// 3. A ready message is sent via RPC to the parent node:
// 
//    - Module: As identified by READY_MODULE
//    - Function: As identified by READY_FUNCTION
//    - Arguments: 2-arity List containing the PID of the virtual mailbox and the READY_VALUE
// 
//    The parent node must return `{:ok, pid}`, echoing the same PID sent, implying successful
//    recognition of the C node.
// 
// Upon ready, all communication with the C node will be done via messages sent to the virtual
// mailbox. The protocol has the following shape:
// 
// - Request: `{:call, sender :: pid(), nonce :: ref(), command :: atom(), payload :: term()}`
// - Response: `{:reply, nonce :: ref(), result :: term()}`
// 
// Currently the following commands are supported:
// 
// - Image Inference
// 
//   - Command: `:infer`
//   - Payload:
// 
//       {
//         width :: non_neg_integer(),
//         height :: non_neg_integer(),
//         format :: :RGB | :I420,
//         orientation :: :upright | :rotated_90_ccw | :rotated_180 | :rotated_90_cw,
//         data :: binary
//       }
// 
//   - Response: `{:ok, list(detection), durations}`, where:
// 
//       detection :: %{
//         required(:x1) => float(),
//         required(:y1) => float(),
//         required(:x2) => float(),
//         required(:y2) => float(),
//         required(:class_id) => non_neg_integer(),
//         required(:score) => float()
//       }
//       duration :: %{
//         required(atom) => non_neg_integer()
//       }
// 

using std::get;
using std::string;
using std::vector;
using std::invalid_argument;
using std::runtime_error;
using cv::Rect;
using cv::Point;
using torch::Tensor;

typedef enum {
  ImageOrientationUpright = 0,
  ImageOrientationRotated90CCW = 1,
  ImageOrientationRotated180 = 2,
  ImageOrientationRotated90CW = 3
} ImageOrientation;

typedef enum {
  ImageFormatUnknown = 0,
  ImageFormatRGBCHW = 1,
  ImageFormatRGBHWC = 2,
  ImageFormatYUV420 = 3
} ImageFormat;

typedef enum {
  ImageSourceMessage = 0,
  ImageSourceSharedMemory = 1
} ImageSource;

typedef int64_t ImageDimension;

typedef struct {
  ImageDimension width;
  ImageDimension height;
  ImageOrientation orientation;
  ImageFormat format;
  ImageSource source;
  void *data;
  size_t length;
} Image;

typedef struct {
  float x1;
  float y1;
  float x2;
  float y2;
  float score;
  unsigned long long class_id;
} Detection;

void setup_erlang(void);
void setup_aten(void);
void setup_torch(void);
void setup_model(void);
void send_ready(void);
void receive_loop(void);
void receive_message(erlang_msg message, ei_x_buff buffer);
ei_x_buff receive_message_infer(erlang_msg message, ei_x_buff buffer, int index_offset);
ei_x_buff process_message_infer(Image image);
void send_reply(erlang_pid from, erlang_ref nonce, ei_x_buff response);
std::string random_name(int length);
int parse_image_orientation(char *in, ImageOrientation *out);
int parse_image_format(char *in, ImageFormat *out);
Tensor build_tensor(Image image);
vector<vector<Detection>> build_detections(Tensor batch, float min_score, float min_iou);

static ei_cnode ErlangNode;
static erlang_pid ErlangPid;
static int ErlangConnection;
static bool ErlangDebug = true;
static torch::Device TorchDevice = torch::kCPU;
static torch::jit::script::Module TorchModel;
#ifdef HAVE_CUDA
  static c10::DeviceIndex TorchDeviceIndex = -1;
#endif

int main(int argc, const char* argv[]) {
  setup_erlang();
  setup_aten();
  setup_torch();
  setup_model();
  send_ready();
  receive_loop();
}

void setup_erlang(void) {
  const char* node_name = getenv("NODE_NAME");
  const char* node_cookie = getenv("NODE_COOKIE");
  const short node_creation = time(NULL) + 1;
  const char* logger_level = getenv("LOGGER_LEVEL");

  if (!node_name) {
    throw invalid_argument("NODE_NAME not set");
  }

  if (!node_cookie) {
    throw invalid_argument("NODE_COOKIE not set");
  }

  if ((0 != ei_init()) || 
      (0 != ei_connect_init(&ErlangNode, random_name(6).c_str(), node_cookie, node_creation)) ||
      (0 >= (ErlangConnection = ei_connect(&ErlangNode, (char*)node_name)))) {
    throw runtime_error("Unable to establish connection");
  }

  if (0 != ei_make_pid(&ErlangNode, &ErlangPid)) {
    throw runtime_error("Unable to create mailbox PID");
  }

  if (logger_level) {
    ErlangDebug = (0 == strcmp(logger_level, "debug"));
  }
}

void setup_aten(void) {
  at::init_num_threads();
}

void setup_torch(void) {
#ifdef HAVE_CUDA
  if (torch::cuda::is_available()) {
    TorchDevice = torch::kCUDA;
    TorchDeviceIndex = 0;
    std::cout << "Using GPU # " << TorchDeviceIndex << " for Inference" << std::endl;
    c10::cuda::setCurrentCUDAStream(c10::cuda::getStreamFromPool(true, TorchDeviceIndex));
  }
#endif
}

void setup_model(void) {
  const char* model_path = getenv("MODEL_PATH");

  if (!model_path) {
    throw invalid_argument("MODEL_PATH not set");
  }

  std::cout << "Loading Model: " << model_path << std::endl;
  TorchModel = torch::jit::load(model_path, TorchDevice);

  if (TorchDevice == torch::kCPU) {
    std::cout << "Using CPU" << std::endl;
    TorchModel.to(torch::kFloat);
  } else if (TorchDevice == torch::kCUDA) {
    std::cout << "Using CUDA" << std::endl;
    TorchModel.to(torch::kHalf);
  }
}

void send_ready(void) {
  const char* ready_module = getenv("READY_MODULE");
  const char* ready_function = getenv("READY_FUNCTION");
  const char* ready_value = getenv("READY_VALUE");

  if (!ready_module) {
    throw invalid_argument("READY_MODULE not set");
  }

  if (!ready_function) {
    throw invalid_argument("READY_FUNCTION not set");
  }

  if (!ready_value) {
    throw invalid_argument("READY_VALUE not set");
  }

  ei_x_buff arguments;
  ei_x_new(&arguments);
  ei_x_encode_list_header(&arguments, 2);
  ei_x_encode_pid(&arguments, &ErlangPid);
  ei_x_encode_string(&arguments, ready_value);
  ei_x_encode_empty_list(&arguments);

  std::cout << "Signalling readiness" << std::endl;
  if (0 > ei_rpc_to(&ErlangNode, ErlangConnection, (char*)ready_module, (char*)ready_function,
                  arguments.buff, arguments.index)) {
    throw runtime_error("Unable to signal readiness via RPC");
  }

  ei_x_buff result;
  ei_x_new_with_version(&result);
  for (;;) {
    erlang_msg message;
    switch (ei_rpc_from(&ErlangNode, ErlangConnection, ERL_NO_TIMEOUT, &message, &result)) {
      case ERL_MSG: {
        int index = 0;
        int version = 0;
        int arity = 0;
        char atom[MAXATOMLEN];
        erlang_pid pid;
        if ((0 > ei_decode_version(result.buff, &index, &version)) ||
            (0 != ei_decode_tuple_header(result.buff, &index, &arity)) ||
            (2 != arity) ||
            (0 > ei_decode_atom(result.buff, &index, atom)) ||
            (0 != strcmp("rex", atom)) ||
            (0 != ei_decode_tuple_header(result.buff, &index, &arity)) ||
            (2 != arity) ||
            (0 > ei_decode_atom(result.buff, &index, atom)) ||
            (0 != strcmp("ok", atom)) ||
            (0 != ei_decode_pid(result.buff, &index, &pid)) ||
            (0 != ei_cmp_pids(&pid, &ErlangPid))) {
          continue;
        }
        std::cout << "Upstream Acknowledged" << std::endl;
        break;
      }
      case ERL_TICK: {
        continue;
      }
      case ERL_ERROR:
      case ERL_TIMEOUT:
      default: {
        throw runtime_error("Unable to signal readiness via RPC");
        break;
      }
    }
    break;
  }

  ei_x_free(&arguments);
  ei_x_free(&result);
}

void receive_loop(void) {
  if (ErlangDebug) {
    std::cout << "Awaiting Message" << std::endl;
  }
  int result;
  do {
    erlang_msg message;
    ei_x_buff buffer;
    ei_x_new(&buffer);
    result = ei_xreceive_msg(ErlangConnection, &message, &buffer);
    if (result == ERL_MSG) {
      if (ErlangDebug) {
        std::cout << "Got Message" << std::endl;
      }
      if ((message.msgtype == ERL_SEND) || (message.msgtype == ERL_REG_SEND)) {
        receive_message(message, buffer);
      }
    }
    ei_x_free(&buffer);
  } while (result != ERL_ERROR);
}

void receive_message(erlang_msg message, ei_x_buff buffer) {
  int version = 0;
  int index = 0;
  int arity = 0;
  erlang_pid from;
  erlang_ref nonce;
  char atom[MAXATOMLEN];

  if (ErlangDebug) {
    std::cout << "Processing Message" << std::endl;
  }

  if ((0 != ei_decode_version(buffer.buff, &index, &version)) ||
      (0 != ei_decode_tuple_header(buffer.buff, &index, &arity)) ||
      (5 != arity) ||
      (0 != ei_decode_atom(buffer.buff, &index, atom)) ||
      (0 != strcmp(atom, "call")) ||
      (0 != ei_decode_pid(buffer.buff, &index, &from)) ||
      (0 != ei_decode_ref(buffer.buff, &index, &nonce)) ||
      (0 != ei_decode_atom(buffer.buff, &index, atom))) {
    throw runtime_error("Unable to decode message");
  }

  if (0 == strcmp(atom, "infer")) {
    ei_x_buff response = receive_message_infer(message, buffer, index);
    send_reply(from, nonce, response);
    ei_x_free(&response);
    return;
  }

  throw runtime_error("Unable to handle command");
}

ei_x_buff receive_message_infer(erlang_msg message, ei_x_buff buffer, int index_offset) {
  int i = 0;
  ei_print_term(stdout, buffer.buff, &i);

  int index = index_offset;
  int arity = 0;
  int type = 0;
  char atom[MAXATOMLEN];
  // {:infer, {width, height, orientation, format, data}}
  long image_width = 0;
  long image_height = 0;
  char image_orientation = ImageOrientationUpright;
  char image_format = ImageFormatUnknown;
  ImageSource image_source = ImageSourceMessage;
  int image_data_term_size = 0;
  int image_data_byte_size = 0;
  void *image_data = NULL;

  if ((0 != ei_decode_tuple_header(buffer.buff, &index, &arity)) ||
      (5 != arity) ||
      (0 != ei_decode_long(buffer.buff, &index, &image_width)) ||
      (0 != ei_decode_long(buffer.buff, &index, &image_height)) ||
      (0 != ei_decode_atom(buffer.buff, &index, atom)) ||
      (0 != parse_image_orientation(atom, (ImageOrientation *)&image_orientation)) ||
      (0 != ei_decode_atom(buffer.buff, &index, atom)) ||
      (0 != parse_image_format(atom, (ImageFormat *)&image_format)) ||
      (0 != ei_get_type(buffer.buff, &index, &type, &image_data_term_size))
  ) {
    throw runtime_error("Unable to parse inference request BBB");
  }

  switch (type) {
    case ERL_BINARY_EXT: {
      long image_length = 0;
      image_data = malloc(image_data_term_size);
      image_data_byte_size = image_data_term_size;
      if (0 != ei_decode_binary(buffer.buff, &index, image_data, &image_length)) {
        throw runtime_error("Unable to extract image binary");
      }
      break;
    }
    case ERL_SMALL_TUPLE_EXT:
    case ERL_LARGE_TUPLE_EXT: {
      image_source = ImageSourceSharedMemory;
      // {:shm, size, capacity, name}
      long shm_size = 0;
      long shm_capacity = 0;
      int shm_name_byte_size = 0;
      char *shm_name = NULL;
      int shm_fd = -1;
      if ((0 != ei_decode_tuple_header(buffer.buff, &index, &arity)) ||
          (4 != arity) ||
          (0 != ei_decode_atom(buffer.buff, &index, atom)) ||
          (0 != strcmp(atom, "shm")) ||
          (0 != ei_decode_long(buffer.buff, &index, &shm_size)) ||
          (0 != ei_decode_long(buffer.buff, &index, &shm_capacity)) ||
          (0 != ei_get_type(buffer.buff, &index, &type, &shm_name_byte_size)) ||
          (ERL_BINARY_EXT != type) ||
          (NULL == (shm_name = (char *)malloc(sizeof(char) * (shm_name_byte_size + 1)))) ||
          (0 != ei_decode_binary(buffer.buff, &index, (void *)shm_name, NULL)) ||
          (-1 == (shm_fd = shm_open(shm_name, O_RDONLY, 0666))) ||
          (NULL == (image_data = mmap(NULL, shm_capacity, PROT_READ, MAP_SHARED, shm_fd, 0))) ||
          (0 != close(shm_fd))
      ) {
        throw runtime_error("Unable to extract image binary via mmap");
      }
      image_data_byte_size = shm_size;
      break;
    }
    default: {
      throw runtime_error("Unable to parse inference request (image data type unknown)");;
    }
  }

  Image image = {
    .width = (ImageDimension)image_width,
    .height = (ImageDimension)image_height,
    .orientation = (ImageOrientation)image_orientation,
    .format = (ImageFormat)image_format,
    .source = image_source,
    .data = image_data,
    .length = (size_t)image_data_byte_size
  };
  ei_x_buff response = process_message_infer(image);
  switch (image.source) {
    case ImageSourceMessage: {
      free(image.data);
      break; 
    }
    case ImageSourceSharedMemory: {
      munmap(image.data, image.length);
      break;
    }
  }
  return response;
}

int parse_image_orientation(char *in, ImageOrientation *out) {
  std::cout << "parsing image orientation " << in << std::endl;

  if (0 == strcmp(in, "upright")) {
    *out = ImageOrientationUpright;
    return 0;
  }
  if (0 == strcmp(in, "rotated_90_ccw")) {
    *out = ImageOrientationRotated90CCW;
    return 0;
  }
  if (0 == strcmp(in, "rotated_180")) {
    *out = ImageOrientationRotated180;
    return 0;
  }
  if (0 == strcmp(in, "rotated_90_cw")) {
    *out = ImageOrientationRotated90CW;
    return 0;
  }
  return -1;
}

int parse_image_format(char *in, ImageFormat *out) {
  std::cout << "parsing image format " << in << std::endl;

  if (0 == strcmp(in, "RGB")) {
    *out = ImageFormatRGBHWC;
    return 0;
  }
  if (0 == strcmp(in, "I420")) {
    *out = ImageFormatYUV420;
    return 0;
  }
  return -1;
}

ei_x_buff process_message_infer(Image image) {
  using std::chrono::duration_cast;
  using std::chrono::microseconds;
  using std::chrono::steady_clock;

  if (ErlangDebug) {
    std::cout << "Processing Inference" << std::endl;
  }
  auto time_started = steady_clock::now();

  Tensor tensor_input = build_tensor(image);
  auto time_loaded = steady_clock::now();

  Tensor tensor_output = TorchModel.forward({tensor_input}).toTuple()->elements()[0].toTensor();
  auto time_executed = steady_clock::now();

  vector<vector<Detection>> lists_detections = build_detections(tensor_output, 0.25, 0.45);
  auto time_processed = steady_clock::now();

  auto duration_load = duration_cast<microseconds>(time_loaded - time_started);
  auto duration_execute = duration_cast<microseconds>(time_executed - time_loaded);
  auto duration_process = duration_cast<microseconds>(time_processed - time_executed);

  ei_x_buff response;
  ei_x_new(&response);
  ei_x_encode_tuple_header(&response, 3);
  ei_x_encode_atom(&response, "ok");
  for (vector<Detection> list_detections: lists_detections) {
    for (Detection detection: list_detections) {
      ei_x_encode_list_header(&response, 1);
      ei_x_encode_map_header(&response, 6);
      ei_x_encode_atom(&response, "x1");
      ei_x_encode_double(&response, detection.x1);
      ei_x_encode_atom(&response, "y1");
      ei_x_encode_double(&response, detection.y1);
      ei_x_encode_atom(&response, "x2");
      ei_x_encode_double(&response, detection.x2);
      ei_x_encode_atom(&response, "y2");
      ei_x_encode_double(&response, detection.y2);
      ei_x_encode_atom(&response, "score");
      ei_x_encode_double(&response, detection.score);
      ei_x_encode_atom(&response, "class_id");
      ei_x_encode_char(&response, ((unsigned char)(detection.class_id)));
    }
  }
  ei_x_encode_empty_list(&response);
  ei_x_encode_list_header(&response, 3);
  ei_x_encode_tuple_header(&response, 2);
  ei_x_encode_atom(&response, "load");
  ei_x_encode_longlong(&response, duration_load.count());
  ei_x_encode_tuple_header(&response, 2);
  ei_x_encode_atom(&response, "execute");
  ei_x_encode_longlong(&response, duration_execute.count());
  ei_x_encode_tuple_header(&response, 2);
  ei_x_encode_atom(&response, "process");
  ei_x_encode_longlong(&response, duration_process.count());
  ei_x_encode_empty_list(&response);
  return response;
  // send_reply(from, nonce, response);
  // ei_x_free(&response);
}

void send_reply(erlang_pid from, erlang_ref nonce, ei_x_buff response) {
  ei_x_buff message;
  ei_x_new_with_version(&message);
  ei_x_encode_tuple_header(&message, 3);
  ei_x_encode_atom(&message, "reply");
  ei_x_encode_ref(&message, &nonce);
  ei_x_append(&message, &response);
  ei_send(ErlangConnection, &from, message.buff, message.index);
}

std::string random_name(int length) {
  std::random_device random_device;
  std::mt19937 random_generator(random_device());
  std::uniform_int_distribution<int> random_distribution{'a', 'z'};
  std::string result(length, '\0');
  for (auto& result_character: result) {
    result_character = random_distribution(random_generator);
  }
  return result;
}

Tensor build_tensor(Image image) {
  ImageDimension width = image.width;
  ImageDimension height = image.height;
  // ImageOrientation orientation = image.orientation;
  // ImageFormat format = image.format;
  void *data = image.data;
  Tensor input = torch::from_blob(data, {width, height, 3}, torch::kByte);

  if (TorchDevice == torch::kCPU) {
    return input.permute({2, 0, 1}).toType(torch::kFloat).div(255).unsqueeze(0);
  } else {
    return input.to(torch::kCUDA, true, true).permute({2, 0, 1}).toType(torch::kFloat16).div(255).unsqueeze(0);
  }
}

Tensor build_xyxy(const Tensor& xywh) {
  auto xyxy = torch::zeros_like(xywh);
  auto cx = xywh.select(1, 0);
  auto cy = xywh.select(1, 1);
  auto w = xywh.select(1, 2);
  auto h = xywh.select(1, 3);
  xyxy.select(1, 0) = cx - w / 2;
  xyxy.select(1, 1) = cy - h / 2;
  xyxy.select(1, 2) = cx + w / 2;
  xyxy.select(1, 3) = cy + h / 2;
  return xyxy;
}

vector<vector<Detection>> build_detections(Tensor batch, float min_score, float min_iou) {
  const auto batch_sizes = batch.sizes();
  const int count_attributes = 5;
  const int count_classes = batch_sizes[2] - count_attributes;
  const int batch_size = batch_sizes[0];
  vector<vector<Detection>> batch_output;

  for (int batch_index = 0; batch_index < batch_size; batch_index++) {
    vector<Detection> frame_output;
    auto predictions = batch.select(0, batch_index);
    auto object_score = predictions.select(1, 4);
    auto class_scores = predictions.slice(1, count_attributes, count_attributes + count_classes);
    auto class_score_max = class_scores.max(1);
    auto class_score = get<0>(class_score_max);
    auto class_id = get<1>(class_score_max);
    auto score = class_score * object_score;
    auto indices = score.ge(min_score).nonzero().select(1, 0);
    int indices_size = indices.size(0);

    if (0 == indices_size) {
      continue;
    }

    auto xyxy = build_xyxy(predictions.slice(1, 0, 4).index_select(0, indices));
    score = score.index_select(0, indices);
    class_id = class_id.index_select(0, indices);

#ifdef HAVE_CUDA
    auto xyxy_cpu = xyxy.to(torch::kCPU, true, true);
    auto score_cpu = score.to(torch::kCPU, true, true);
    auto class_id_cpu = class_id.to(torch::kCPU, true, true);
    c10::cuda::getCurrentCUDAStream(TorchDeviceIndex).synchronize();
#else
    auto xyxy_cpu = xyxy;
    auto score_cpu = score;
    auto class_id_cpu = class_id;
#endif

    auto xyxy_accessor = xyxy_cpu.accessor<float_t, 2>();
    auto score_accessor = score_cpu.accessor<float_t, 1>();
    auto class_id_accessor = class_id_cpu.accessor<int64_t, 1>();

    vector<cv::Rect> boxes;
    vector<float> scores;
    vector<int> indices_nms;
    for (int i = 0; i < indices_size; i++) {
      Point x1y1 = Point(xyxy_accessor[i][0], xyxy_accessor[i][1]);
      Point x2y2 = Point(xyxy_accessor[i][2], xyxy_accessor[i][3]);
      boxes.emplace_back(Rect(x1y1, x2y2));
      scores.emplace_back(score_accessor[i]);
    }
    cv::dnn::NMSBoxes(boxes, scores, min_score, min_iou, indices_nms);

    for (int index_nms: indices_nms) {
      Detection item;
      item.x1 = xyxy_accessor[index_nms][0];
      item.y1 = xyxy_accessor[index_nms][1];
      item.x2 = xyxy_accessor[index_nms][2];
      item.y2 = xyxy_accessor[index_nms][3];
      item.score = score_accessor[index_nms];
      item.class_id = class_id_accessor[index_nms];
      frame_output.emplace_back(item);
    }
    batch_output.emplace_back(frame_output);
  }

  return batch_output;
}
