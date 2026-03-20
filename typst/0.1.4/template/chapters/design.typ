#import "reporter_architecture.typ": reporter_architecture
#import "translator_architecture.typ": translator_architecture
#import "modeling_pipeline.typ": modeling_pipeline

#let design() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)


  #reporter_architecture("../assets/reporter.jpg")

  #translator_architecture()

  #modeling_pipeline()
]
