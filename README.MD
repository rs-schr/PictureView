# PureImage Browser

Ein performanter, leichtgewichtiger und plattformunabhängiger Bildbetrachter, entwickelt mit PureBasic 6.21. Die Software bietet eine flüssige Benutzererfahrung durch asynchrone Hintergrundverarbeitung und optimierte Darstellung auf mehreren Monitoren.

## Inhaltsverzeichnis
1. Features
2. Technische Logik
3. Installation (Linux)
4. Bedienung
5. Screenshots
6. Technische Details

---

## Features
* Multi-Format Support: Unterstützung für JPG, JPEG und PNG (inklusive Dekodierung und Enkodierung).
* Asynchrones Threading: Thumbnails werden im Hintergrund generiert, um die GUI-Reaktionszeit nicht zu beeinträchtigen.
* Intelligente Slideshow: Filterung nach Wildcards (z.B. urlaub*.jpg), einstellbare Intervalle und Zufallswiedergabe.
* Multi-Monitor Fullscreen: Erkennt automatisch den aktuellen Monitor und öffnet die Vollbildvorschau auf dem entsprechenden Display.
* Dateiverwaltung: Integrierte Funktionen zum Löschen und Navigieren in der Verzeichnisstruktur.

---

## Technische Logik
Die Software basiert auf drei Hauptpfeilern:

1. Event-Loop & UI: Ein zentraler Main-Loop verarbeitet System-Events. Das Layout ist dynamisch und passt sich beim Resizing der Fenstergröße an (Update_Layout).
2. Thread-Safe Data Handling: Da die Bildliste (ListFiles) sowohl vom UI-Thread als auch vom Background_Thumbnail_Worker gelesen und beschrieben wird, ist der Zugriff konsequent über einen Mutex abgesichert. Dies verhindert Race-Conditions und Abstürze unter Linux (Debian/Ubuntu).
3. Scaling & Rendering: Bilder werden mittels Letterboxing in der Prozedur Draw_Image_To_Canvas auf das Canvas-Gadget gezeichnet. Dabei wird das Seitenverhältnis strikt beibehalten, während ungenutzte Flächen mit einer Hintergrundfarbe gefüllt werden.

---

## Installation (Linux)
Da PureBasic unter Linux native Bibliotheken nutzt, müssen für die Kompilierung und Ausführung auf Debian oder Ubuntu folgende Pakete installiert sein:

sudo apt-get update
sudo apt-get install build-essential libxine2-dev libxxf86vm-dev libxsk-dev libgl1-mesa-dev libglu1-mesa-dev libgtk-3-dev libwebkit2gtk-4.0-dev libvlc-dev libcanberra-gtk3-module

---

## Bedienung
* Navigation: Nutzen Sie den ExplorerTree auf der linken Seite, um Verzeichnisse zu wählen. Die Liste aktualisiert sich automatisch bei Verzeichniswechsel.
* Filterung: Über das ComboBox-Menü können Sie gezielt nach JPG oder PNG filtern.
* Vorschau: Ein Klick auf ein Bild in der Liste zeigt dieses sofort im Vorschaufenster an.
* Fullscreen: Drücken Sie F11, um zwischen Fenster- und Vollbildmodus zu wechseln. Escape beendet die Slideshow.
* Slideshow: Über den Button "Slideshow" öffnet sich ein Dialog. Dort können Sie Wildcard-Filter (z.B. "IMG_2025*") und das Zeitintervall festlegen.

---

## Screenshots

[Image Placeholder: Main_Interface_Overview]
Abbildung 1: Die Hauptoberfläche mit dem Explorer-Baum, der Dateiliste und den Steuerungselementen für Rotation, Umbenennung und Löschvorgänge.

[Image Placeholder: Slideshow_Settings_Dialog]
Abbildung 2: Der Konfigurationsdialog für die Slideshow mit Filter-Eingabe, Intervalls-Spin-Gadget und Randomize-Option.

[Image Placeholder: Fullscreen_Preview_Mode]
Abbildung 3: Der rahmenlose Vollbildmodus inklusive halbtransparentem Status-Overlay am unteren Bildschirmrand, das den Fortschritt der Slideshow visualisiert.

---

## Technische Details
* Programmiersprache: PureBasic 6.21 (LTS)
* Compiler-Optionen: Thread-Safe (aktiviert), Unicode-Modus.
* OS-Kompatibilität: 
  - Windows: Volle Unterstützung (Win 10/11).
  - Linux: Optimiert für Ubuntu 22.04 / Debian 12 (GTK3).
* Kodierungs-Standards: 
  - Variablen: CamelCase (z.B. targetPath)
  - Funktionen: snake_case (z.B. scan_directory)
  - Klassen: PascalCase (z.B. ImageEntry)

---

## Lizenz
Dieses Projekt wurde für die effiziente Bildverwaltung unter Linux und Windows optimiert.

