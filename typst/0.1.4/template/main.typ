#import "lib.typ": *

#import "acknowledgements.typ": acknowledgements
#import "abstract.typ": abstract
#import "abbreviations.typ": abbreviations


// cd C:\Users\Administrator\Desktop\thesis\typst\0.1.4
//typst watch --root . template/main.typ
#import "chapters/introduction.typ": introduction
#import "chapters/methodology.typ": methodology
#import "chapters/summary.typ": summary


#show: project.with(
  lang: "en",
  authors: (
    (
      name: "Elmer Dema",
      id: "22211551",
      email: "elmer.dema@stud.th-deg.de/ elmerdema2022@gmail.com",
    ),
  ),
  title: "QoE Prediction from Encrypted Traffic with MARINA on P4/Tofino",
  subtitle: "Supervisor: Prof. Dr. Andreas Kassler",
  date: datetime.today().display(),
  version: none,
  thesis-compliant: true,

  // Format
  side-margins: (
    left: 3.5cm,
    right: 3.5cm,
    top: 3.5cm,
    bottom: 3.5cm,
  ),
  h1-spacing: 0.5em,
  line-spacing: 0.65em,
  font: default-font,
  font-size: 11pt,
  hyphenate: false,

  // Color settings
  primary-color: dark-blue,
  secondary-color: blue,
  text-color: dark-grey,
  background-color: light-blue,

  // Cover sheet
  custom-cover-sheet: none,
  cover-sheet: (
    university: (
      name: "TH Deggendorf",
      street: "Dieter-Görlitz-Platz 1",
      city: "Deggendorf",
      logo: image("assets/logo_thd.jpg"),
    ),
    cover-image: none,
    description: [
      Bachelor Thesis
    ],
    faculty: "Applied Informatics",
    programme: "Artificial Intelligence Bsc",
    semester: "WS2025",
    examiner: "Prof. Andreas Kassler",
    submission-date: datetime.today().display(),
  ),

  // Declaration
  custom-declaration: image("assets/form.pdf", width: 100%, height: 100%),
  declaration-on-the-final-thesis: none,

  acknowledgements: acknowledgements(),
  abstract: abstract(),

  // Outlines
  outlines-indent: 1em,
  depth-toc: 4, // Wenn `thesis-compliant` true ist, dann wird es auf 4 gesetzt wenn hier none steht
  show-list-of-figures: false, // Wird immer angezeigt, wenn `thesis-compliant` true ist
  show-list-of-abbreviations: true, // Achtung: Schlägt fehl wenn glossary leer ist und trotzdem dargestellt werden soll!
  list-of-abbreviations: abbreviations(),
  show-list-of-formulas: true, // Setze es auf false, wenn es nicht angezeigt werden soll
  custom-outlines: (
    // none
    (
      title: none, // required
      custom: none, // required
    ),
  ),
  show-list-of-tables: true, // Setze es auf false, wenn es nicht angezeigt werden soll
  show-list-of-todos: false, // Setze es auf false, wenn es nicht angezeigt werden soll
  literature-and-bibliography: bibliography(bib-file, title: none, style: "ieee", full: false),
)

#show: additional-styling

= Introduction<einleitung>

#introduction()

= Methodology

#methodology()

= Benchmarks<zusammenfassung>

#summary()
