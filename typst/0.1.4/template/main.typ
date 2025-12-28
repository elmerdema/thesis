#import "lib.typ": *

#import "abstract.typ": abstract
#import "abbreviations.typ": abbreviations

// Kapitel
// https://github.com/typst/packages/blob/main/packages/preview/aio-studi-and-thesis/0.1.4/docs/example-de-thesis.pdf
#import "chapters/introduction.typ": introduction
#import "chapters/summary.typ": summary
// Füge hier weitere Kapitel hinzu


#show: project.with(
  lang: "en",
  authors: (
    (
      name: "Elmer Dema",
      id: "22211551",
      email: "elmer.dema@stud.th-deg.de/ elmerdema2022@gmail.com"
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
    bottom: 3.5cm
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
      logo: image("assets/logo_thd.jpg")
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
  custom-declaration: none,
  declaration-on-the-final-thesis: (
    legal-reference: none,
    thesis-name: none,
    consent-to-publication-in-the-library: none,
    genitive-of-university: none
  ),

  abstract: abstract(),

  // Outlines
  outlines-indent: 1em,
  depth-toc: 4,                     // Wenn `thesis-compliant` true ist, dann wird es auf 4 gesetzt wenn hier none steht
  show-list-of-figures: false,      // Wird immer angezeigt, wenn `thesis-compliant` true ist
  show-list-of-abbreviations: true, // Achtung: Schlägt fehl wenn glossary leer ist und trotzdem dargestellt werden soll!
  list-of-abbreviations: abbreviations(),
  show-list-of-formulas: true, // Setze es auf false, wenn es nicht angezeigt werden soll
  custom-outlines: ( // none
    (
      title: none,   // required
      custom: none   // required
    ),
  ),
  show-list-of-tables: true,   // Setze es auf false, wenn es nicht angezeigt werden soll
  show-list-of-todos: false,    // Setze es auf false, wenn es nicht angezeigt werden soll
  literature-and-bibliography: bibliography(bib-file, title: none, style: "ieee", full: false),
)

#show: additional-styling

= Introduction<einleitung>

#introduction()

= Hauptteil

// Hier sollten die einzelnen Kapitel aufgerufen werden, welche zuvor unter `chapters` angelegt wurden

== Beispiele

// Aufruf einer Abkürzung
#gls("repo-vorlage")

// Referenz zu einer anderen Überschrift
@einleitung

// Zitieren aus der Bibliographie
Siehe @noauthor_bibliography_nodate

// Verwendung von Inhalten aus der Bibliographie
#bib.noauthor_citegeist_nodate.fields.title

// TODO anlegen
#todo[Das ist ein Beispiel]

= Schluss/Zusammenfassung/Fazit<zusammenfassung>

#summary()
