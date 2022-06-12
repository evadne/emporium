import "../css/screen-generic.css"

import "phoenix_html"
import topbar from "topbar"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {MembraneWebRTC, Peer, SerializedMediaEvent, TrackContext} from "@jellyfish-dev/membrane-webrtc-js";

let WebRTC = {
  async setupStream () {
    let originalMediaDevices = await navigator.mediaDevices.enumerateDevices()
    if (!(originalMediaDevices.some((device) => device.kind === "videoinput"))) {
      throw new Error("No video input")
    }
    await navigator.mediaDevices.getUserMedia({audio: false, video: true})
    let mediaDevices = await navigator.mediaDevices.enumerateDevices()
    let videoDevices = mediaDevices.filter((device) => device.kind === "videoinput")
    let videoStream = null
    for (const videoDevice of videoDevices) {
      try {
        videoStream = await navigator.mediaDevices.getUserMedia({
          video: {
            width: { max: 1280, ideal: 1280, min: 320 },
            height: { max: 720, ideal: 720, min: 320 },
            frameRate: { max: 30, ideal: 24 },
            deviceId: { exact: videoDevice.deviceId },
            facingMode: { exact: 'environment' }
          }
        });
        console.log('got stream', videoStream)
        break
      } catch (error) {
        console.error("Error while getting local video stream", videoDevice, error)
      }
    }
    if (!videoStream) {
      // No environment cam, try looser constraints
      for (const videoDevice of videoDevices) {
        try {
          videoStream = await navigator.mediaDevices.getUserMedia({
            video: {
              width: { max: 1280, ideal: 1280, min: 320 },
              height: { max: 720, ideal: 720, min: 320 },
              frameRate: { max: 30, ideal: 24 },
              deviceId: { exact: videoDevice.deviceId }
            }
          });
          break
        } catch (error) {
          console.error("Error while getting local video stream", videoDevice, error)
        }
      }
    }
    if (!videoStream) {
      throw new Error("Unable to acquire video stream")
    }
    return videoStream
  },
  setupElement (element, stream) {
    element.autoplay = true
    element.playsInline = true
    element.muted = true
    element.srcObject = stream
  }
}

let WebRTCHook = {
  mounted () {
    window.addEventListener(`phx:acquire-streams`, (e) => {
      WebRTC.setupStream().then((videoStream) => {
        this.videoStream = videoStream
        this.videoElement = this.el.querySelector('video#webrtc-video');
        WebRTC.setupElement(this.videoElement, this.videoStream)
        this.pushEvent("streams-acquired", {})
      }).catch((error) => {
        this.pushEvent("error", {reason: error.message})
      })
    })
    window.addEventListener(`phx:connect-session`, (e) => {
      this.peerID = e.detail.peer_id
      this.sessionID = e.detail.session_id
      this.membraneSession = new MembraneWebRTC({
        callbacks: {
          onSendMediaEvent: (mediaEvent) => {
            this.pushEvent("mediaEvent", {data: mediaEvent})
          },
          onConnectionError: (message) => {
            this.pushEvent("error", {reason: message})
          },
          onJoinSuccess: (peerID, peers) => {
            let trackSettings = null;
            this.videoStream.getTracks().forEach((track) => {
              trackSettings = track.getSettings()
              this.videoTrackID = this.membraneSession.addTrack(
                track,
                this.videoStream,
                {},
                { enabled: true, active_encodings: ["h"] }
              )
            })
            this.pushEvent("connected", {
              video: {
                width: trackSettings.width,
                height: trackSettings.height
              }
            })
          },
          onJoinError: (metadata) => {
            this.pushEvent("error", {reason: metadata})
          }
        }
      });
      this.membraneSession.join({
        displayName: this.peerID
      });
    })
    window.addEventListener(`phx:handle-media-event`, (e) => {
      this.membraneSession.receiveMediaEvent(e.detail.data)
    });
    window.addEventListener(`phx:handle-simulcast-config`, (e) => {
      return;
    });
  }
}

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})

let liveSocket = new LiveSocket("/live", Socket, {
  params: {
    _csrf_token: document.querySelector("meta[name='csrf-token']").getAttribute("content")
  },
  hooks: {
    WebRTC: WebRTCHook
  }
})

liveSocket.connect()

window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())
window.liveSocket = liveSocket
