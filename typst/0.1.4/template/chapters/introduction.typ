#let introduction() = [
  #set par(
  first-line-indent: 1em,
  spacing: 0.65em,
  justify: true,
)
Machine Learning (ML) is a subgroup of Artificial Intelligence (AI), a field where computers autonomously learn from past data to generate 
predictions or solutions. Recently, there has been a surge in applying ML methods to address practical challenges within 
computer networks @izima_video_quality_prediction. This thesis implements and extends recent applications of ML techniques that employ Quality of Experience (QoE) metrics to predict video quality. 
These QoE measurements are essential for capturing the end-to-end performance of network services @vega_resilience_video_streaming.
As video data makes up the majority of global IP traffic @cisco_vni_2017_2022, network operators are under pressure to optimize resource management while satisfying 
user demands. In general, Video Quality Assessment (VQA) has relied on both subjective @itu_p910_video_quality and objective @chikkerur_objective_video_quality_assessment methodologies. Subjective methods focus 
on quantifying the end-user's satisfaction. Consequently, network traffic management driven by Quality of Experience (QoE) depends on monitoring and forecasting 
application-level performance or QoE via video Key Performance Indicators (KPIs) that impact the user. The International Telecommunication Union (ITU) characterizes 
QoE as the overall experience of a service from the subjective viewpoint of the end user @itu_g1011_qoe_assessment.

#figure(
  image("../assets/cisco.jpeg", width: 90%),
  caption: [
    According to #link("https://www.cisco.com/c/en/us/solutions/collateral/executive-perspectives/annual-internet-report/white-paper-c11-741490.html")[
      Cisco
    ]Cisco, Video effect of the devices on traffic is more pronounced because of the introduction of Ultra-High-Definition (UHD), or 4K, video streaming.
    #link("https://www.statista.com/chart/2349/consumer-data-traffic-2013-to-2018/")[
      Source
    ]
  ],
)

A significant obstacle in video streaming is the absence of a standardized method for measuring QoE @bentaleb_survey_bitrate_adaptation, which has stimulated research into QoE models derived from network statistics. 
Such modeling assists in defining specific KPIs for various user categories. For example, network providers might analyze tools like rebuffering or quality switching to understand their impact on the video stream. 

  This helps quantify the effect on user QoE and correlates these issues with network parameters such as jitter or delay. While subjective studies offer reliable evaluations, they are noted for being expensive, time intensive and 
impractical for real-world applications @duanmu_qoe_index_streaming_video. Meanwhile, objective VQA uses mathematical models to estimate perceived quality. Although metrics such as Peak Signal-to-Noise Ratio (PSNR) @huynh_thu_scope_validity_psnr and Structural Similarity Index (SSIM) 
are computationally efficient, 
they do not always accurately mirror the actual user experience @wang_ssim_image_quality_assessment @wolf_psnr_video_sequence.  
The main focus in this thesis is on network performance rather than direct user experience, where we will be estimating QoE based on buffering events (stalling, depleting, etc.)
]