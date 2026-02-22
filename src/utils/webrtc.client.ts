/**
 * Drone Streamer Portal VR Engine - Nuxt / Vue TS Interface
 * MediaMTX WebRTC Client (WHEP Compatible)
 */

export interface WebRTCClientOptions {
  url: string
  videoElement: HTMLVideoElement
  onConnect?: () => void
  onDisconnect?: () => void
  onError?: (error: Error) => void
}

export class WebRTCClient {
  private peerConnection: RTCPeerConnection | null = null
  private url: string
  private videoElement: HTMLVideoElement
  private isConnected = false
  private options: WebRTCClientOptions

  constructor(options: WebRTCClientOptions) {
    this.options = options
    this.url = options.url
    this.videoElement = options.videoElement
  }

  public async connect(): Promise<void> {
    try {
      this.peerConnection = new RTCPeerConnection()

      // Add a transceiver to receive video and audio
      this.peerConnection.addTransceiver('video', { direction: 'recvonly' })
      this.peerConnection.addTransceiver('audio', { direction: 'recvonly' })

      this.peerConnection.ontrack = (event) => {
        const stream = event.streams[0] || null
        if (this.videoElement.srcObject !== stream) {
          this.videoElement.srcObject = stream
        }
      }

      this.peerConnection.onconnectionstatechange = () => {
        if (!this.peerConnection) return

        const state = this.peerConnection.connectionState
        if (state === 'connected' && !this.isConnected) {
          this.isConnected = true
          this.options.onConnect?.()
        } else if (state === 'disconnected' || state === 'failed') {
          this.isConnected = false
          this.options.onDisconnect?.()
        }
      }

      // Create Offer
      const offer = await this.peerConnection.createOffer()
      await this.peerConnection.setLocalDescription(offer)

      // Wait for ICE gathering to complete (MediaMTX requires all candidates in the SDP for WHEP usually, or vanilla trickle ICE)
      await new Promise<void>((resolve) => {
        if (this.peerConnection?.iceGatheringState === 'complete') {
          resolve()
        } else {
          const checkState = () => {
            if (this.peerConnection?.iceGatheringState === 'complete') {
              this.peerConnection.removeEventListener('icegatheringstatechange', checkState)
              resolve()
            }
          }
          this.peerConnection?.addEventListener('icegatheringstatechange', checkState)

          // Fallback timeout in case ICE gathering hangs
          setTimeout(() => {
            this.peerConnection?.removeEventListener('icegatheringstatechange', checkState)
            resolve()
          }, 3000)
        }
      })

      // MediaMTX WHEP Endpoint expecting the fully gathered SDP offer
      // we append /whep to the url automatically if it's missing
      const endpoint = this.url.endsWith('/whep') ? this.url : `${this.url}/whep`

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/sdp',
        },
        body: this.peerConnection.localDescription?.sdp || offer.sdp,
      })

      if (!response.ok) {
        throw new Error(`MediaMTX returned status ${response.status}`)
      }

      const answerSdp = await response.text()

      // Set Remote Description from MediaMTX
      const answer = new RTCSessionDescription({
        type: 'answer',
        sdp: answerSdp,
      })

      await this.peerConnection.setRemoteDescription(answer)
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error))
      this.options.onError?.(err)
      this.disconnect()
    }
  }

  public disconnect(): void {
    if (this.peerConnection) {
      this.peerConnection.close()
      this.peerConnection = null
    }
    this.isConnected = false
    this.videoElement.srcObject = null
    this.options.onDisconnect?.()
  }
}
