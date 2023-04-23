# Hot Dog Emporium

End-to-end showcase of MLOps for Elixir ecosystem.

## Preamble

There is a scarcity of end-to-end [ModelOps](https://en.wikipedia.org/wiki/ModelOps) projects made available to aid understanding of the state of the art and to demonstrate how such solutions may be deployed on custom infrastructure.

Therefore the Emporium was erected with the purpose of illustrating practical implementation techniques for Elixir teams, and secondarily to assess end-to-end performance of such implementations, which will surely become popular over time.

The Emporium assumes the following canonical architecture:

- x86_64 system, macOS or Linux
- Optional Nvidia CUDA-capable GPU

For more context, check out:

- [“Not Hotdog” Revisited, ElixirConf EU 2023](https://speakerdeck.com/evadne/not-hotdog-revisited)

## Preparing the System

The application requires the following dependencies:

1.  LLVM / Clang (Run: `./vendor/setup-clang.sh`)

2.  CMake (Run: `apt-get install cmake`)

3.  LibTorch (run `./vendor/setup-libtorch.sh`)

4.  FFMpeg (Run: `apt-get install ffmpeg`)

5.  OpenCV (Run: `./vendor/setup-libtorch.sh`)

6.  Nvidia’s CUDA Toolkit (if using GPU)

## Preparing the Models

This application comes with 2 models:

1.  Image Classification via ResNet-50

2.  Object Detection via YOLOv5

The former is pulled by Bumblebee therefore no action is required.

For the latter, clone YOLOv5 and export the pre-trained model:

    $ git clone https://github.com/ultralytics/yolov5 ultralytics-yolov5
    $ cd ultralytics-yolov5; asdf local python 3.8.5; cd -; cd -
    $ pip install -r requirements.txt
    $ python3 export.py --weights yolov5s.pt --include torchscript

Then copy `yolov5s.torchscript` to:

    apps/emporium_inference_yolov5/priv/yolov5s.torchscript

You can also use other sizes by configuration:

    config :emporium_runner_yolov5, model_name: "yolov5x.torchscript"

## Architecture

The system is split into the following sections:

The **Emporium Environment** application is responsible for foundational services, including node clustering (enabling Erlang Distribution between nodes), and setting up of facilities that would allow custom Horde supervisors in other applications to function correctly.

The **Emporium Proxy** application provides entry point for HTTP traffic (TLS is offloaded to the load balancer) and manages proxying of all connections to other applications such as Emporium Web, or if required, an Admin app in the future.

The **Emporium Web** application provides the entry point, and hosts the Session LiveView, which is the main interaction element.

The **Emporium Nexus** application provides WebRTC ingress and orchestration for inference workloads. It hosts the Membrane framework, exposes RTP endpoints. and allows WebRTC connections to be made to the application cluster.

The **Emporium Inference** application is a façade, which holds image conversion logic, via Evision, which is used in featurisation (pre-processing).

The **Emporium Inference (YOLOv5)** application provides Object Detection capabilities via YOLOv5, orchestrated via Sbroker, and implemented with PyTorch using a custom C++ program.

The **Emporium Inference (ResNet)** application provides Image Classification capabilities via Bumblebee and the `microsoft/resnet-50` model.

## Installation & Setup

To prepare the environment, install the prerequisites above, then install the CUDA Toolkit which you can find at [CUDA Downloads](https://developer.nvidia.com/cuda-downloads), if you are using an NVidia GPU on Linux.

Note if you are using WSL 2, then select Linux → x86_64 → WSL-Ubuntu → 2.0. It is critical not to use normal versions for Ubuntu as that would install drivers, which are not necessary for WSL 2, where the driver is already installed on Windows side.

To change between Object Recognition and Image Classification, modify `EmporiumNexus.InferenceSink`.

At a bare minimum, you should configure `config/dev.env` with the template at `config/dev.env.template`:

- `NGROK_SUBDOMAIN`: Is used when running ngrok as specified in Procfile
- `SECRET_KEY_BASE`: Is used for Phoenix dead & live views
- `TURN_IP`, `TURN_MOCK_IP` should be publicly routable from your clients for TCP/UDP TURN traffic
- `TURN_PORT_UDP_FROM`, `TURN_PORT_UDP_TO` should be a high range e.g. 50000 - 65535
` `HOST` should be your ngrok URL

You may run into some problems which are documented in “Common Problems”.

## Pending Tasks

- Investigate real time display of metrics

- Investigate YOLOv8

- Investigate operational pattern for TensorRT

- Investigate deployment topology / AWS CFN

- Investigate IPv6 usage

## Common Problems

### Unable to acquire Media Devices

This may be related to whether you have used HTTPS or not. WebRTC requires a [secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts) and the fastest way to acquire full compliance would be to configure and use [ngrok](https://ngrok.com) then use the ngrok domain for all testing purposes.

For local deployment, consider CloudFlare Zero Trust / CloudFlare Access.

### Unable to compile FastTLS dependency

FastTLS is a dependency of the Membrane Framework.

On Linux, as long as `pkg-config` exists, it should be found automatically, but this can be a problem on macOS. It is a [known problem](https://github.com/membraneframework/membrane_videoroom#known-issues) and the workaround is as follows:

    export LDFLAGS="-L/usr/local/opt/openssl/lib"
    export CFLAGS="-I/usr/local/opt/openssl/include/"
    export CPPFLAGS="-I/usr/local/opt/openssl/include/"
    export PKG_CONFIG_PATH="/usr/local/opt/openssl@3/lib/pkgconfig:$PKG_CONFIG_PATH"
    mix deps.compile fast_tls

### Unable to compile YOLOv5 Runner

When no `CMAKE_CUDA_COMPILER` could be found, it may be due to improper configuration of the CUDA Toolkit.

Consider adding the following to `~/.zshrc` or equivalent:

    export CUDA_HOME=/usr/local/cuda
    export PATH=$CUDA_HOME/bin:$PATH

Once `nvcc` can be found, this problem resolves itself.

### Unable to establish WebRTC Connections

Membrane’s WebRTC implementation includes an integrated TURN server, so you should set both `TURN_IP` and `TURN_MOCK_IP`…

- `TURN_IP` is the IP on the interface that the TURN server listens to
- `TURN_MOCK_IP` is the IP that is presented to the client

…to publicly routable IPs.

See the following post for more information:

- [How we made Membrane SFU less ICE-y](https://medium.com/membraneframework/how-we-made-membrane-sfu-less-ice-y-9625472ec386)

### YOLOv5 — PyTorch / nvFuser issue

This is under investigation, a workaround has been put in place ([issue](https://github.com/pytorch/pytorch/issues/99781))

If not using a 40-series card, you may downgrade libTorch to 1.3.x by:

    rm -rf ./vendor/libtorch
    LIBTORCH_VERSION=1.3.0 ./vendor/setup-libtorch.sh
