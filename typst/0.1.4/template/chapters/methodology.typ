#import "reporter_architecture.typ": reporter_architecture
#import "modeling_pipeline.typ": modeling_pipeline
#import "pforest_implementation.typ": pforest_implementation
#import "translator_evaluation.typ": translator_evaluation
#let methodology() = [

  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  #reporter_architecture("../assets/reporter.jpg")

  == Dataset analysis
  The dataset used in this thesis originates from #link("https://zenodo.org/records/14724247")[Karagkioules et al. paper.] 
  The dataset is designed to fill this gap by providing measurements that were simultaneously obtained at the network, transport, and application layers. The data were generated using YouTube’s native Android application on two smartphone models at two locations in Europe over a period of more than five months. 

  At the application layer, a wide range of adaptive streaming parameters was extracted from YouTube’s mobile client. This was made possible by a recently introduced Wrapper App @seufert_wrapper_youtube_android, which enables remote control and monitoring of YouTube’s native Android application. At the transport and network layers, the commonly used tool tcpdump @tcpdump_packet_analyzer was used to record unfiltered packet logs on both the smartphones and a gateway. 
  
  The dataset includes measurements from 8 different scenarios, each representing a different quality and rate limiter. However, Scenario 6 is used since it provides automatic quality selection without any rate limiting, which closely resembles real-world conditions. @karagkioules_youtube_mobile_dataset

  #figure(
    image("../assets/youtube_dataset.png", width: 50%),
    caption: [
      #link("https://d-nb.info/1311242007/34")[Hardware] setup for regulated and automatic HAS traffic measurements
    ],
  )

  === Data Ingestion and Parsing
  This chapter explains the pipeline designed to transform raw network traces and application logs into a structured dataset suitable for machine learning analysis. The pipeline, implemented in Python, handles data ingestion from log file formats and statistical feature extraction.
  
  #figure(
    box(fill: luma(240), inset: 8pt, radius: 9pt, width: 100%)[
      #set align(left)
      #raw("(15174 IP(tos 0x0,ttl 55,id 0,offset 0,flags[DF],protoUDP(17),length 1378)74.125.105.91.443>192.168.10.200.4864: UDP, length 135)", lang: "python")
    ],
    caption: [Sample line from TCPdump network trace log showing a packet with timestamp and length.]
  )

  The raw data for "Scenario 6" was distributed across a directory structure organized by Video ID and Iteration number. Each iteration contained two distinct data sources: network traffic logs (TCPdump) and application performance metrics (Phone Statistics). To ingest this data, custom parsing functions were developed to handle the semi-structured nature of the logs.

  For the network traces, a regular expression was used to extract the timestamp and packet size (length) from each line of the TCPdump output. The regex pattern used to capture these groups is defined below:

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      #raw("r'(?P<timestamp>\d+\.\d+).*? length (?P<length>\d+)'", lang: "python")
    ],
    caption: [Regular expression pattern used to extract packet arrival times and payload lengths.]
  )

  On the other side, the application logs required a two-step parsing process. The parser first identified lines containing JSON objects embedded within the log text. It then extracted the JSON string, corrected formatting inconsistencies (such as trailing braces), and parsed the object to retrieve the ground-truth labels: Bandwidth Estimate (`bwe`) and Buffer Level (`buffer_level_ms`). 

  === Synchronization and Preprocessing
  A critical challenge in this pipeline was aligning the timelines of the two data sources. The application logs recorded timestamps in a timezone differing from the network traces. To rectify this, a one-hour offset was added to the application statistics indices ($bold(t_"stats" + 1"h")$). 
  
  Furthermore, to ensure that the feature set captured the context relevant to the video session, the network packets were filtered to a specific time range. This range was defined dynamically as the interval $bold([t_"min" - 10"s", t_"max" + 10"s"])$, where $bold(t_"min")$ and $bold(t_"max")$ represent the start and end of the application logging period.

  === Feature Engineering and Windowing
  The transformation from raw packet logs to model-ready features involved computing instantaneous metrics followed by a temporal aggregation. The system used a non-overlapping time window of *50ms*. 

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      TIME_WINDOW = '50ms'

      #agg_rules defines how to aggregate each metric within the time window
      #this includes sums for traffic volume and moments, as well as counts for packet occurrences
      features_df = packets_df.resample(TIME_WINDOW).agg(agg_rules)
      features_df.columns = [
          'ps_sum', 'packet_count', 'ps2_sum', 'ps3_sum', 
          'iat_sum', 'iat2_sum', 'iat3_sum', 'jitter_sum'
      ]
      ```
    ],
    caption: [Pandas resampling operation to aggregate packet-level metrics into 50ms time windows.]
  )

  #pagebreak()
  First, specific metrics were calculated for every packet $i$ in the stream. The Inter-Arrival Time ($"IAT"$) was derived as the difference in timestamps between consecutive packets. Jitter was calculated as the absolute difference between consecutive IAT values. To capture the higher-order statistical properties of the traffic flow, the second and third moments (squares and cubes) were computed for both packet size ($"PS"$) and $"IAT"$.

  These values were then resampled into 50ms buckets. The aggregation rules applied to generate the final feature vector $X_t$ for each window $t$ are detailed in Table 1.

  #figure(
    table(
      columns: (auto, 2fr, 2fr),
      inset: 10pt,
      align: left,
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Feature Name*], [*Mathematical Derivation*], [*Aggregation Method*],
      
      [Packet Count], 
      [Count of events in window], 
      [Sum],

      [Traffic Volume ($"PS"$)], 
      [$sum "PS"_i$], 
      [Sum],

      [Traffic Moments], 
      [$"PS"^2, "PS"^3$], 
      [Sum (of squares/cubes)],

      [IAT Total], 
      [$Delta t = t_i - t_(i-1)$], 
      [Sum],

      [IAT Moments], 
      [$"IAT"^2, "IAT"^3$], 
      [Sum (of squares/cubes)],

      [Jitter], 
      [$|"IAT"_i - "IAT"_(i-1)|$], 
      [Mean (Sum / Count)]
    ),
    caption: [Definition of features extracted per 50ms time window.]
  )

  #figure(
  table(
    columns: (auto, 1fr, 1fr),
    inset: 10pt,
    align: (col, row) => if col == 0 { left } else { right },
    fill: (col, row) => if row == 0 { luma(230) } else { none },
    //  divider line under the header
    stroke: (col, row) => if row == 0 { (bottom: 0.7pt + black) } else { (bottom: 0.5pt + luma(200)) },

    [*Statistic*], [*Jitter(ms)*], [*Buffer Level (ms)*],

    [Count], [163,090], [163,090],
    [Mean], [40.78], [105,381.84],
    [Std Dev], [441.41], [29,514.49],
    [50% (Median)], [1.2], [120,077.00],
    [75% (Q3)], [1.78], [122,075.75],
    [Max], [9,231.11], [129,857.00],
  ),
  caption: [Summary statistics for Jitter and Buffer Level across the processed dataset.]
) <tab:dataset_summary>

  #pagebreak()
  === Target Alignment and Dataset Construction
  The final stage of the pipeline merged the high-frequency network features with the lower-frequency application labels. Since the application statistics (Buffer Level and BWE) were logged at irregular intervals, a standard join was insufficient. Instead, a `merge_asof` (nearest key) strategy was implemented.
  
  For each 50ms feature window, the system located the nearest application log entry. A strict tolerance limit of *100ms* was enforced; if no application label existed within 100ms of the window's timestamp, the sample was discarded. This ensured that the model would not learn from stale state information.
  
  Post-merge, the dataset underwent a cleaning phase where any rows containing `NaN` values for the target variables were dropped. The final output consisted of a CSV file containing approximately 163,000 samples, encompassing the feature vector, the target labels, and identifiers for the video and iteration. 
  

  #figure(
    grid(
      columns: (1fr, 1fr),
      gutter: 10pt,
      image("../assets/feature_distro.png", width: 100%, height: auto),
      image("../assets/graph_bwe.png", width: 100%),
    ),
    caption: [ (Left) Feature distributions (log scale); (Right) Bandwidth vs Buffer Level over time.]
  )

#modeling_pipeline()

#pforest_implementation()

#pagebreak()
#translator_evaluation()

]