EnableExplicit

; ============================================================================
; PROTOTYPES & DECLARATIONS
; ============================================================================
Declare Update_Layout()
Declare Draw_Image_To_Canvas(ImagePath.s)
Declare Scan_Directory(Path.s, FilterIdx.i)
Declare Rotate_Selected_Image(Direction.i) 
Declare Rename_Selected_Image()            
Declare Move_Selected_Image()              
Declare Open_Preview_Window(Fullscreen.b)
Declare Background_Thumbnail_Worker(Value.i)
Declare.b Match_Pattern(FileName.s, Pattern.s)
Declare Open_Slideshow_Dialog()
Declare Prepare_Slideshow_List()
Declare Stop_Slideshow_Logic()
Declare Draw_Slideshow_Status()

; ============================================================================
; CONSTANTS & ENUMERATIONS
; ============================================================================
Enumeration Windows
  #WinMain
  #WinPreview
  #WinSlideshow
EndEnumeration

Enumeration Gadgets
  #TreeDir
  #ListImages
  #ComboFilter
  #CanvasPreview
  #BtnRotateLeft
  #BtnRotateRight
  #BtnRename
  #BtnMove
  #BtnDelete
  #BtnSlideshow
  #SlideFilter
  #SlidePause
  #SlideRandom
  #SlideStart
EndEnumeration

Enumeration Shortcuts
  #Shortcut_Toggle_Fullscreen
  #Shortcut_Exit_Slideshow
  #Shortcut_Delete_File
EndEnumeration

#Timer_Slideshow = 1
#Event_Thumbnail_Ready = #PB_Event_FirstCustomValue

; ============================================================================
; STRUCTURES & GLOBALS
; ============================================================================
Structure ImageEntry
  FileName.s
  FullPath.s
  HasThumbnail.b
  ThumbnailID.i 
EndStructure

Global NewList ListFiles.ImageEntry()    ; Liste der gefundenen Bilder
Global NewList SlideshowIndices.i()     ; Indizes für die Slideshow-Reihenfolge
Global CurrentPath.s                    ; Aktuell angezeigtes Verzeichnis
Global IsFullscreen.b = #False          ; Status des Vorschaufensters
Global IsSlideshow.b = #False           ; Status der Slideshow-Automatik
Global SlideshowPattern.s = "*"         ; Wildcard-Filter für Slideshow
Global SlideshowRandom.b = #False        ; Zufallswiedergabe aktiv?
Global SlideshowInterval.i = 5          ; Sekunden pro Bild
Global PrevX, PrevY, PrevW = 800, PrevH = 600 ; Fensterstatus vor Fullscreen
Global ThumbnailSize = 64               ; Feste Größe der Thumbnails
Global ThreadID.i, Mutex.i = CreateMutex() ; Mutex für thread-sicheren Listenzugriff

; ============================================================================
; PROCEDURES - LOGIC
; ============================================================================

; Prüft, ob ein Dateiname auf ein Wildcard-Pattern passt
Procedure.b Match_Pattern(FileName.s, Pattern.s)
  If Pattern = "*" Or Pattern = "" : ProcedureReturn #True : EndIf
  Protected p.s = LCase(Pattern), f.s = LCase(FileName)
  If Right(p, 1) = "*"
    If Left(f, Len(p)-1) = Left(p, Len(p)-1) : ProcedureReturn #True : EndIf
  Else
    If f = p : ProcedureReturn #True : EndIf
  EndIf
  ProcedureReturn #False
EndProcedure

; Zeichnet den Fortschrittsbalken und Infos in das Slideshow-Canvas
Procedure Draw_Slideshow_Status()
  Protected total = ListSize(SlideshowIndices())
  If total = 0 : ProcedureReturn : EndIf
  Protected current = ListIndex(SlideshowIndices()) + 1
  Protected w = GadgetWidth(#CanvasPreview), h = GadgetHeight(#CanvasPreview)
  Protected progressW = (w * current) / total
  If StartDrawing(CanvasOutput(#CanvasPreview))
    DrawingMode(#PB_2DDrawing_AlphaBlend)
    Box(0, h - 40, w, 40, RGBA(0, 0, 0, 180))
    Box(0, h - 6, progressW, 6, RGBA(0, 255, 255, 255))
    DrawingMode(#PB_2DDrawing_Transparent)
    DrawText(15, h - 35, "Bild: " + Str(current) + " / " + Str(total), RGB(255, 255, 255))
    StopDrawing()
  EndIf
EndProcedure

; Beendet die Slideshow-Logik und räumt Timer auf
Procedure Stop_Slideshow_Logic()
  If IsSlideshow
    IsSlideshow = #False
    RemoveWindowTimer(#WinMain, #Timer_Slideshow)
    SetGadgetText(#BtnSlideshow, "Slideshow")
    If IsFullscreen
      IsFullscreen = #False
      Open_Preview_Window(#False)
      Update_Layout()
    EndIf
  EndIf
EndProcedure

; Rotiert das gewählte Bild physisch auf der Festplatte
Procedure Rotate_Selected_Image(Direction.i)
  Protected idx = GetGadgetState(#ListImages), img, rotatedImg, path.s
  Protected x, y, w, h
  If idx = -1 : ProcedureReturn : EndIf
  
  LockMutex(Mutex)
  SelectElement(ListFiles(), idx)
  path = ListFiles()\FullPath
  UnlockMutex(Mutex)
  
  img = LoadImage(#PB_Any, path)
  If img
    w = ImageWidth(img) : h = ImageHeight(img)
    ; Neues Image mit vertauschten Dimensionen für 90° Drehung
    rotatedImg = CreateImage(#PB_Any, h, w, 32)
    
    If rotatedImg
      ; Array zur Zwischenspeicherung der Pixeldaten (verhindert verschachtelte Drawing-Blöcke)
      Dim Pixels(w - 1, h - 1)
      
      ; Schritt 1: Pixel aus Original lesen
      If StartDrawing(ImageOutput(img))
        For y = 0 To h - 1
          For x = 0 To w - 1
            Pixels(x, y) = Point(x, y)
          Next
        Next
        StopDrawing()
      EndIf
      
      ; Schritt 2: Pixel in Ziel schreiben (rotiert)
      If StartDrawing(ImageOutput(rotatedImg))
        For y = 0 To h - 1
          For x = 0 To w - 1
            If Direction = 1 ; Rechts 90°
              Plot((h - 1) - y, x, Pixels(x, y))
            Else           ; Links 90°
              Plot(y, (w - 1) - x, Pixels(x, y))
            EndIf
          Next
        Next
        StopDrawing()
      EndIf
      
      ; Schritt 3: Speichern (überschreiben)
      If LCase(GetExtensionPart(path)) = "png"
        SaveImage(rotatedImg, path, #PB_ImagePlugin_PNG)
      Else
        SaveImage(rotatedImg, path, #PB_ImagePlugin_JPEG, 95)
      EndIf
      
      FreeImage(rotatedImg)
    EndIf
    FreeImage(img)
    
    ; Thumbnail im Cache als ungültig markieren
    LockMutex(Mutex) : ListFiles()\HasThumbnail = #False : UnlockMutex(Mutex)
    Draw_Image_To_Canvas(path)
  EndIf
EndProcedure

; Benennt die Datei physisch um
Procedure Rename_Selected_Image()
  Protected idx = GetGadgetState(#ListImages), oldName.s, newName.s, path.s
  If idx = -1 : ProcedureReturn : EndIf
  LockMutex(Mutex)
  SelectElement(ListFiles(), idx)
  oldName = ListFiles()\FileName
  path = GetPathPart(ListFiles()\FullPath)
  UnlockMutex(Mutex)
  newName = InputRequester("Bild umbenennen", "Neuer Dateiname:", oldName)
  If newName <> "" And newName <> oldName
    If RenameFile(path + oldName, path + newName)
      Scan_Directory(path, GetGadgetState(#ComboFilter))
    EndIf
  EndIf
EndProcedure

; Verschiebt die Datei in ein anderes Verzeichnis
Procedure Move_Selected_Image()
  Protected idx = GetGadgetState(#ListImages), oldPath.s, newDir.s, fileName.s
  If idx = -1 : ProcedureReturn : EndIf
  LockMutex(Mutex)
  SelectElement(ListFiles(), idx)
  oldPath = ListFiles()\FullPath
  fileName = ListFiles()\FileName
  UnlockMutex(Mutex)
  newDir = PathRequester("Zielverzeichnis wählen", GetPathPart(oldPath))
  If newDir <> ""
    ; RenameFile funktioniert unter Linux auch als 'mv' (Move)
    If RenameFile(oldPath, newDir + fileName)
      Scan_Directory(GetPathPart(oldPath), GetGadgetState(#ComboFilter))
    EndIf
  EndIf
EndProcedure

; Erstellt eine Liste von Indizes für die Slideshow (Filter & Random)
Procedure Prepare_Slideshow_List()
  ClearList(SlideshowIndices())
  Protected i, count = CountGadgetItems(#ListImages)
  For i = 0 To count - 1
    LockMutex(Mutex) 
    SelectElement(ListFiles(), i)
    If Match_Pattern(ListFiles()\FileName, SlideshowPattern)
      AddElement(SlideshowIndices()) : SlideshowIndices() = i
    EndIf 
    UnlockMutex(Mutex)
  Next
  ; Fisher-Yates Shuffle für Zufallswiedergabe
  If SlideshowRandom And ListSize(SlideshowIndices()) > 1
    Protected j, size = ListSize(SlideshowIndices())
    For i = size - 1 To 1 Step -1
      j = Random(i) 
      SelectElement(SlideshowIndices(), i) : Protected valI = SlideshowIndices()
      SelectElement(SlideshowIndices(), j) : Protected valJ = SlideshowIndices()
      SelectElement(SlideshowIndices(), i) : SlideshowIndices() = valJ
      SelectElement(SlideshowIndices(), j) : SlideshowIndices() = valI
    Next
  EndIf
  FirstElement(SlideshowIndices())
EndProcedure

; Slideshow-Konfigurationsdialog
Procedure Open_Slideshow_Dialog()
  If OpenWindow(#WinSlideshow, 0, 0, 300, 180, "Slideshow Einstellungen", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#WinMain))
    TextGadget(#PB_Any, 10, 15, 280, 20, "Namens-Filter (*):")
    StringGadget(#SlideFilter, 10, 35, 280, 25, SlideshowPattern)
    TextGadget(#PB_Any, 10, 70, 140, 20, "Intervall (Sek):")
    SpinGadget(#SlidePause, 10, 90, 60, 25, 1, 3600, #PB_Spin_Numeric)
    SetGadgetState(#SlidePause, SlideshowInterval)
    CheckBoxGadget(#SlideRandom, 150, 90, 130, 25, "Zufällig")
    SetGadgetState(#SlideRandom, SlideshowRandom)
    ButtonGadget(#SlideStart, 10, 135, 280, 35, "Slideshow starten")
  EndIf
EndProcedure

; Passt Gadget-Größen bei Fenster-Resizing an
Procedure Update_Layout()
  Protected winW = WindowWidth(#WinMain), winH = WindowHeight(#WinMain)
  If winW < 500 : winW = 500 : EndIf
  If winH < 400 : winH = 400 : EndIf
  ResizeGadget(#TreeDir, 5, 45, 250, winH - 55)
  ResizeGadget(#ComboFilter, 260, 45, winW - 270, 30)
  ResizeGadget(#ListImages, 260, 80, winW - 270, winH - 90)
EndProcedure

; Zeichnet das aktuelle Bild skaliert in das Vorschau-Canvas
Procedure Draw_Image_To_Canvas(ImagePath.s)
  Protected img, canvasW, canvasH, imgW, imgH, targetW, targetH, x, y, factor.f
  If IsGadget(#CanvasPreview)
    canvasW = GadgetWidth(#CanvasPreview) : canvasH = GadgetHeight(#CanvasPreview)
    img = LoadImage(#PB_Any, ImagePath)
    If img
      imgW = ImageWidth(img) : imgH = ImageHeight(img)
      ; Proportionale Skalierung berechnen
      factor = canvasW / imgW
      If (imgH * factor) > canvasH : factor = canvasH / imgH : EndIf
      targetW = imgW * factor : targetH = imgH * factor
      x = (canvasW - targetW) / 2 : y = (canvasH - targetH) / 2
      
      If StartDrawing(CanvasOutput(#CanvasPreview))
        Box(0, 0, canvasW, canvasH, RGB(15, 15, 15)) ; Hintergrund
        If targetW > 0 And targetH > 0
          ResizeImage(img, targetW, targetH, #PB_Image_Raw)
          DrawImage(ImageID(img), x, y)
        EndIf
        StopDrawing()
      EndIf
      FreeImage(img)
      If IsSlideshow : Draw_Slideshow_Status() : EndIf
    EndIf
  EndIf
EndProcedure

; Hintergrund-Thread für die Thumbnail-Generierung (verhindert UI-Lag)
Procedure Background_Thumbnail_Worker(Value.i)
  Protected img, i, size
  Repeat
    LockMutex(Mutex) : size = ListSize(ListFiles()) : UnlockMutex(Mutex)
    If size > 0
      For i = 0 To size - 1
        LockMutex(Mutex)
        If i < ListSize(ListFiles())
          SelectElement(ListFiles(), i)
          If ListFiles()\HasThumbnail = #False
            img = LoadImage(#PB_Any, ListFiles()\FullPath)
            If img
              ResizeImage(img, ThumbnailSize, ThumbnailSize, #PB_Image_Raw)
              ListFiles()\ThumbnailID = img
              ListFiles()\HasThumbnail = #True
              ; UI über neues Thumbnail informieren
              PostEvent(#Event_Thumbnail_Ready, #WinMain, #ListImages, 0, i)
            EndIf
          EndIf
        EndIf
        UnlockMutex(Mutex) : Delay(5)
      Next
    EndIf
    Delay(500)
  ForEver
EndProcedure

; Scannt das Verzeichnis und füllt die Liste
Procedure Scan_Directory(Path.s, FilterIdx.i)
  Protected dir, ext.s
  If Right(Path, 1) <> #PS$ : Path + #PS$ : EndIf
  CurrentPath = Path
  LockMutex(Mutex)
  ClearList(ListFiles()) : ClearGadgetItems(#ListImages)
  dir = ExamineDirectory(#PB_Any, Path, "*.*")
  If dir
    While NextDirectoryEntry(dir)
      If DirectoryEntryType(dir) = #PB_DirectoryEntry_File
        ext = LCase(GetExtensionPart(DirectoryEntryName(dir)))
        Select FilterIdx
          Case 0 : If ext <> "jpg" And ext <> "jpeg" And ext <> "png" : Continue : EndIf
          Case 1 : If ext <> "jpg" And ext <> "jpeg" : Continue : EndIf
          Case 2 : If ext <> "png" : Continue : EndIf
        EndSelect
        AddElement(ListFiles())
        ListFiles()\FileName = DirectoryEntryName(dir)
        ListFiles()\FullPath = Path + ListFiles()\FileName
        ListFiles()\HasThumbnail = #False
      EndIf
    Wend
    FinishDirectory(dir)
    ; Sortierung nach Dateiname
    SortStructuredList(ListFiles(), #PB_Sort_Ascending | #PB_Sort_NoCase, OffsetOf(ImageEntry\FileName), TypeOf(ImageEntry\FileName))
    ForEach ListFiles() 
      AddGadgetItem(#ListImages, -1, Chr(10) + ListFiles()\FileName) 
    Next
  EndIf 
  UnlockMutex(Mutex)
EndProcedure

; Steuert das Vorschaufenster (Normal oder Fullscreen)
Procedure Open_Preview_Window(Fullscreen.b)
  Protected targetDesktop = 0, i, centerX, idx
  ExamineDesktops()
  If IsWindow(#WinPreview)
    If IsFullscreen = #False 
      PrevX = WindowX(#WinPreview) : PrevY = WindowY(#WinPreview) 
      PrevW = WindowWidth(#WinPreview) : PrevH = WindowHeight(#WinPreview) 
    EndIf
    centerX = WindowX(#WinPreview) + WindowWidth(#WinPreview) / 2
    For i = 0 To ExamineDesktops() - 1
      If centerX >= DesktopX(i) And centerX < (DesktopX(i) + DesktopWidth(i)) : targetDesktop = i : Break : EndIf
    Next
    CloseWindow(#WinPreview)
  EndIf
  If Fullscreen
    OpenWindow(#WinPreview, DesktopX(targetDesktop), DesktopY(targetDesktop), DesktopWidth(targetDesktop), DesktopHeight(targetDesktop), "Vorschau", #PB_Window_BorderLess)
    StickyWindow(#WinPreview, #True) : IsFullscreen = #True
  Else
    OpenWindow(#WinPreview, PrevX, PrevY, PrevW, PrevH, "Vorschau", #PB_Window_SizeGadget | #PB_Window_SystemMenu)
    StickyWindow(#WinPreview, #False) : IsFullscreen = #False
  EndIf
  CanvasGadget(#CanvasPreview, 0, 0, WindowWidth(#WinPreview), WindowHeight(#WinPreview), #PB_Canvas_Keyboard)
  AddKeyboardShortcut(#WinPreview, #PB_Shortcut_F11, #Shortcut_Toggle_Fullscreen)
  AddKeyboardShortcut(#WinPreview, #PB_Shortcut_Escape, #Shortcut_Exit_Slideshow)
  idx = GetGadgetState(#ListImages)
  If idx <> -1 : LockMutex(Mutex) : SelectElement(ListFiles(), idx) : Draw_Image_To_Canvas(ListFiles()\FullPath) : UnlockMutex(Mutex) : EndIf
EndProcedure

; ============================================================================
; MAIN ENTRY POINT
; ============================================================================
UseJPEGImageDecoder() : UseJPEGImageEncoder() : UsePNGImageDecoder() : UsePNGImageEncoder()

; Verzeichnis aus Parametern oder Arbeitsverzeichnis
CurrentPath = ProgramParameter(0)
If CurrentPath = "" Or FileSize(CurrentPath) <> -2 : CurrentPath = GetCurrentDirectory() : EndIf

; Hauptfenster-Setup
OpenWindow(#WinMain, 50, 50, 1100, 750, "PureImage Browser", #PB_Window_SystemMenu | #PB_Window_SizeGadget | #PB_Window_MaximizeGadget)
ButtonGadget(#BtnRotateLeft, 5, 5, 80, 35, "<- Drehen")
ButtonGadget(#BtnRotateRight, 90, 5, 80, 35, "Drehen ->")
ButtonGadget(#BtnRename, 175, 5, 100, 35, "Umbenennen")
ButtonGadget(#BtnMove, 280, 5, 100, 35, "Verschieben")
ButtonGadget(#BtnDelete, 385, 5, 100, 35, "Löschen")
ButtonGadget(#BtnSlideshow, 490, 5, 130, 35, "Slideshow")

ExplorerTreeGadget(#TreeDir, 5, 45, 250, 690, CurrentPath, #PB_Explorer_NoFiles | #PB_Explorer_AlwaysShowSelection)
ComboBoxGadget(#ComboFilter, 260, 45, 735, 30)
AddGadgetItem(#ComboFilter, -1, "Bilder (JPG, PNG)") : SetGadgetState(#ComboFilter, 0)
ListIconGadget(#ListImages, 260, 80, 735, 655, "Vorschau", 80, #PB_ListIcon_FullRowSelect)
AddGadgetColumn(#ListImages, 1, "Dateiname", 500)

AddKeyboardShortcut(#WinMain, #PB_Shortcut_F11, #Shortcut_Toggle_Fullscreen)
AddKeyboardShortcut(#WinMain, #PB_Shortcut_Delete, #Shortcut_Delete_File)

Update_Layout()
Open_Preview_Window(#False)
Scan_Directory(CurrentPath, 0)
ThreadID = CreateThread(@Background_Thumbnail_Worker(), 0)

Define event, eventWin, selectedIdx, currentIdx, targetPath.s

; ============================================================================
; EVENT LOOP
; ============================================================================
Repeat
  event = WaitWindowEvent()
  eventWin = EventWindow()
  
  Select event
    Case #PB_Event_SizeWindow
      If eventWin = #WinMain : Update_Layout() 
      ElseIf eventWin = #WinPreview 
        ResizeGadget(#CanvasPreview, 0, 0, WindowWidth(#WinPreview), WindowHeight(#WinPreview))
        selectedIdx = GetGadgetState(#ListImages)
        If selectedIdx <> -1 : LockMutex(Mutex) : SelectElement(ListFiles(), selectedIdx) : Draw_Image_To_Canvas(ListFiles()\FullPath) : UnlockMutex(Mutex) : EndIf
      EndIf
      
    Case #PB_Event_Timer
      If EventTimer() = #Timer_Slideshow And IsSlideshow
        If ListSize(SlideshowIndices()) > 0
          If NextElement(SlideshowIndices()) = 0 : Prepare_Slideshow_List() : EndIf 
          currentIdx = SlideshowIndices() : SetGadgetState(#ListImages, currentIdx)
          LockMutex(Mutex) : SelectElement(ListFiles(), currentIdx) : Draw_Image_To_Canvas(ListFiles()\FullPath) : UnlockMutex(Mutex)
        EndIf
      EndIf

    Case #PB_Event_Menu
      Select EventMenu()
        Case #Shortcut_Toggle_Fullscreen : IsFullscreen = 1 - IsFullscreen : Open_Preview_Window(IsFullscreen)
        Case #Shortcut_Exit_Slideshow : Stop_Slideshow_Logic()
        Case #Shortcut_Delete_File
          selectedIdx = GetGadgetState(#ListImages)
          If selectedIdx <> -1
            LockMutex(Mutex) : SelectElement(ListFiles(), selectedIdx) : targetPath = ListFiles()\FullPath : UnlockMutex(Mutex)
            If MessageRequester("Löschen", "Datei wirklich löschen?", #PB_MessageRequester_YesNo) = #PB_MessageRequester_Yes
              If DeleteFile(targetPath) : Scan_Directory(CurrentPath, GetGadgetState(#ComboFilter)) : EndIf
            EndIf
          EndIf
      EndSelect

    Case #PB_Event_Gadget
      Select EventGadget()
        Case #BtnRotateLeft : Rotate_Selected_Image(0)
        Case #BtnRotateRight : Rotate_Selected_Image(1)
        Case #BtnRename : Rename_Selected_Image()
        Case #BtnMove : Move_Selected_Image()
        Case #BtnDelete : PostEvent(#PB_Event_Menu, #WinMain, #Shortcut_Delete_File)
        Case #BtnSlideshow : If IsSlideshow : Stop_Slideshow_Logic() : Else : Open_Slideshow_Dialog() : EndIf
        Case #SlideStart 
          SlideshowPattern = GetGadgetText(#SlideFilter) : SlideshowInterval = GetGadgetState(#SlidePause)
          SlideshowRandom = GetGadgetState(#SlideRandom) : CloseWindow(#WinSlideshow) : Prepare_Slideshow_List()
          If ListSize(SlideshowIndices()) > 0 
            IsSlideshow = #True : SetGadgetText(#BtnSlideshow, "Stop")
            AddWindowTimer(#WinMain, #Timer_Slideshow, SlideshowInterval * 1000)
            currentIdx = SlideshowIndices() : SetGadgetState(#ListImages, currentIdx)
            LockMutex(Mutex) : SelectElement(ListFiles(), currentIdx) : Draw_Image_To_Canvas(ListFiles()\FullPath) : UnlockMutex(Mutex)
            If IsFullscreen = #False : Open_Preview_Window(#True) : EndIf
          EndIf
        Case #TreeDir : If EventType() = #PB_EventType_Change : Scan_Directory(GetGadgetText(#TreeDir), GetGadgetState(#ComboFilter)) : EndIf
        Case #ListImages : If EventType() = #PB_EventType_Change : selectedIdx = GetGadgetState(#ListImages)
            If selectedIdx <> -1 : LockMutex(Mutex) : SelectElement(ListFiles(), selectedIdx) : Draw_Image_To_Canvas(ListFiles()\FullPath) : UnlockMutex(Mutex) : EndIf : EndIf
      EndSelect

    Case #PB_Event_CloseWindow
      If eventWin = #WinMain : If IsThread(ThreadID) : KillThread(ThreadID) : EndIf : End : Else : CloseWindow(eventWin) : EndIf
      
    Case #Event_Thumbnail_Ready
      selectedIdx = EventData()
      LockMutex(Mutex)
      If selectedIdx >= 0 And selectedIdx < ListSize(ListFiles())
        SelectElement(ListFiles(), selectedIdx)
        If ListFiles()\HasThumbnail And IsImage(ListFiles()\ThumbnailID)
          SetGadgetItemImage(#ListImages, selectedIdx, ImageID(ListFiles()\ThumbnailID))
        EndIf
      EndIf
      UnlockMutex(Mutex)
  EndSelect
Until event = #PB_Event_CloseWindow
; IDE Options = PureBasic 6.30 (Linux - x64)
; CursorPosition = 369
; FirstLine = 336
; Folding = ---
; EnableThread
; EnableXP
; DPIAware
; Executable = pictureview
; CommandLine = /home/rolf/Nextcloud/Hochzeit/