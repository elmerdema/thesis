#import "../lib.typ": *
#let introduction() = [
  #set par(
    first-line-indent: 1em,
    spacing: 0.65em,
    justify: true,
  )

  #abbr("ml") is a subgroup of Artificial Intelligence (#abbr("ai")), a field where computers autonomously learn from past data to generate
  predictions or solutions. Recently, there has been a surge in applying #abbr("ml") methods to address practical challenges within
  computer networks @izima_video_quality_prediction. This thesis implements and extends recent applications of #abbr("ml") techniques that use #abbr("qoe") metrics to predict video quality.
  These #abbr("qoe") measurements are essential for capturing the end-to-end performance of network services @vega_resilience_video_streaming.
  As video data makes up the majority of global #abbr("ip") traffic @cisco_vni_2017_2022, network operators are under pressure to optimize resource management while satisfying
  user demands. In general, Video Quality Assessment (#abbr("vqa")) has relied on both subjective @itu_p910_video_quality and objective @chikkerur_objective_video_quality_assessment methodologies. Subjective methods focus
  on quantifying the end-user's satisfaction. Consequently, network traffic management driven by #abbr("qoe") depends on monitoring and forecasting
  application-level performance or #abbr("qoe") via video Key Performance Indicators (#abbrpl("kpi")) that impact the user. The International Telecommunication Union (#abbr("itu")) characterizes
  #abbr("qoe") as the overall experience of a service from the subjective viewpoint of the end user @itu_g1011_qoe_assessment.

  #figure(
    image("../assets/cisco.jpeg", width: 90%),
    caption: [
      Video effect of the devices on traffic is more pronounced because of the introduction of Ultra-High-Definition (#abbr("uhd")), or 4K, video streaming.
      #link("https://www.statista.com/chart/2349/consumer-data-traffic-2013-to-2018/")[
        Source
      ]
    ],
  )

  #pagebreak()
  A significant obstacle in video streaming is the absence of a standardized method
  #footnote[The P.1203 model was validated only for #link("https://docs.aveq.info/surfmeter-docs/reference/video-qoe-model")[certain content conditions ]
    (e.g., video up to 1080p and  25 fps). Extrapolating beyond these ranges (e.g., 4K, high fps content) may create unreliable quality estimates unless updated or extended versions are used.]
  for measuring #abbr("qoe") @bentaleb_survey_bitrate_adaptation, which has stimulated research into #abbr("qoe") models derived from network statistics.

  Such modeling assists in defining specific #abbrpl("kpi") for various user categories. For example, network providers might analyze tools like rebuffering or quality switching to understand their impact on the video stream.

  This helps analyze the effect on user #abbr("qoe") and correlates these issues with network parameters such as jitter or delay. While subjective studies offer reliable evaluations, they are noted for being expensive, time intensive and
  impractical for real-world applications @duanmu_qoe_index_streaming_video. Meanwhile, objective #abbr("vqa") uses mathematical models to estimate perceived quality. Although metrics such as Peak Signal-to-Noise Ratio (#abbr("psnr")) @huynh_thu_scope_validity_psnr and Structural Similarity Index (#abbr("ssim"))
  are computationally efficient,
  they do not always accurately mirror the actual user experience @wang_ssim_image_quality_assessment @wolf_psnr_video_sequence.

  The main focus in this thesis is on network performance rather than direct user experience.
  Because the proposed system operates directly within the switch, the focus is placed on network-layer parameters rather than application-layer metrics, with #abbr("qoe") estimated from buffering-related events (e.g., stalling and depletion).

  #figure(
    image("../assets/low_streaming.jpg", width: 90%),
    caption: [
      #link("https://www.mdpi.com/2079-9292/14/13/2587")[
        MPEG
      ] DASH is a scenario where a video player dynamically switches between different quality levels of media segments delivered over HTTP to adapt to fluctuating network conditions for smooth playback.
    ],
  )
]
