EnableExplicit

; Plugins für Linux
UseJPEGImageDecoder() : UseJPEGImageEncoder()
UsePNGImageDecoder() : UsePNGImageEncoder()

; ============================================================================
; KONSTANTEN & STRUKTUREN
; ============================================================================
Enumeration Windows : #WinMain : #WinPreview : #WinSlideshow : EndEnumeration
Enumeration Gadgets
  #TreeDir : #ListImages : #CanvasPreview
  #BtnRotateLeft : #BtnRotateRight : #BtnRename : #BtnDelete : #BtnSlideshow
  #SlidePause : #SlideRandom : #SlideStart : #TxtPause : #SlideFilter
 EndEnumeration
  
Enumeration Shortcuts : #Shortcut_F11 : #Shortcut_ESC : EndEnumeration

#Timer_Slideshow = 1
#Event_Thumbnail_Ready = #PB_Event_FirstCustomValue
#Event_Update_Image    = #PB_Event_FirstCustomValue + 1

Structure ImageEntry 
  FileName.s : FullPath.s : HasThumbnail.b : ThumbnailID.i 
EndStructure

Global NewList ListFiles.ImageEntry(), NewList SlideshowIndices.i()
Global CurrentPath.s, IsFullscreen.b = #False, IsSlideshow.b = #False
Global SlideshowInterval.i = 3, SlideshowRandom.b = #False, SlideshowPattern.s = "*"
Global PrevX = 100, PrevY = 100, PrevW = 800, PrevH = 600 
Global ThumbnailSize = 64, Mutex.i = CreateMutex(), Quit.b = #False

; ============================================================================
; HILFSFUNKTIONEN
; ============================================================================

Procedure.b Match_Pattern(String.s, Pattern.s)
  Protected reg = CreateRegularExpression(#PB_Any, "^" + ReplaceString(ReplaceString(Pattern, ".", "\."), "*", ".*") + "$", #PB_RegularExpression_NoCase)
  Protected result.b = #False
  If reg
    If MatchRegularExpression(reg, String) : result = #True : EndIf
    FreeRegularExpression(reg)
  EndIf
  ProcedureReturn result
EndProcedure

Procedure Draw_Image_To_Canvas(ImagePath.s)
  Protected img, cw, ch, tw, th, factor.f
  If IsGadget(#CanvasPreview) And FileSize(ImagePath) > 0
    img = LoadImage(#PB_Any, ImagePath)
    If img
      cw = GadgetWidth(#CanvasPreview) : ch = GadgetHeight(#CanvasPreview)
      If cw > 10 And ch > 10
        factor = cw / ImageWidth(img) : If (ImageHeight(img) * factor) > ch : factor = ch / ImageHeight(img) : EndIf
        tw = ImageWidth(img) * factor : th = ImageHeight(img) * factor
        If StartDrawing(CanvasOutput(#CanvasPreview))
          Box(0, 0, cw, ch, RGB(25, 25, 25))
          DrawImage(ImageID(img), (cw - tw) / 2, (ch - th) / 2, tw, th)
          StopDrawing()
        EndIf
      EndIf : FreeImage(img)
    EndIf
  EndIf
EndProcedure

Procedure Open_Preview_Window(Fullscreen.b)
  If IsWindow(#WinPreview)
    If IsFullscreen = #False
      PrevX = WindowX(#WinPreview) : PrevY = WindowY(#WinPreview)
      PrevW = WindowWidth(#WinPreview) : PrevH = WindowHeight(#WinPreview)
    EndIf
    CloseWindow(#WinPreview)
  EndIf
  ExamineDesktops()
  If Fullscreen
    OpenWindow(#WinPreview, 0, 0, DesktopWidth(0), DesktopHeight(0), "", #PB_Window_BorderLess)
    IsFullscreen = #True
  Else
    OpenWindow(#WinPreview, PrevX, PrevY, PrevW, PrevH, "Vorschau", #PB_Window_SystemMenu | #PB_Window_SizeGadget)
    IsFullscreen = #False
  EndIf
  CanvasGadget(#CanvasPreview, 0, 0, WindowWidth(#WinPreview), WindowHeight(#WinPreview))
  AddKeyboardShortcut(#WinPreview, #PB_Shortcut_F11, #Shortcut_F11)
  AddKeyboardShortcut(#WinPreview, #PB_Shortcut_Escape, #Shortcut_ESC)
  PostEvent(#Event_Update_Image)
EndProcedure

Procedure Scan_Directory(Path.s)
  Protected dir, ext.s
  If Path = "" : ProcedureReturn : EndIf
  If Right(Path, 1) <> #PS$ : Path + #PS$ : EndIf
  CurrentPath = Path
  dir = ExamineDirectory(#PB_Any, Path, "*.*")
  LockMutex(Mutex) 
  ForEach ListFiles() : If IsImage(ListFiles()\ThumbnailID) : FreeImage(ListFiles()\ThumbnailID) : EndIf : Next
  ClearList(ListFiles()) : ClearGadgetItems(#ListImages)
  If dir
    While NextDirectoryEntry(dir)
      If DirectoryEntryType(dir) = #PB_DirectoryEntry_File
        ext = LCase(GetExtensionPart(DirectoryEntryName(dir)))
        If ext="jpg" Or ext="jpeg" Or ext="png"
          AddElement(ListFiles()) : ListFiles()\FileName = DirectoryEntryName(dir)
          ListFiles()\FullPath = Path + ListFiles()\FileName
        EndIf
      EndIf
    Wend : FinishDirectory(dir)
    SortStructuredList(ListFiles(), #PB_Sort_Ascending | #PB_Sort_NoCase, OffsetOf(ImageEntry\FileName), TypeOf(ImageEntry\FileName))
    ForEach ListFiles() : AddGadgetItem(#ListImages, -1, Chr(10) + ListFiles()\FileName) : Next
  EndIf : UnlockMutex(Mutex)
  If ListSize(ListFiles()) > 0 : SetGadgetState(#ListImages, 0) : PostEvent(#Event_Update_Image) : EndIf
EndProcedure

Procedure Background_Thumbnail_Worker(Value.i)
  Protected img, i, total
  While Not Quit
    LockMutex(Mutex) : total = ListSize(ListFiles()) : UnlockMutex(Mutex)
    For i = 0 To total - 1
      If Quit : Break : EndIf
      LockMutex(Mutex)
      If i < ListSize(ListFiles()) : SelectElement(ListFiles(), i)
        If ListFiles()\HasThumbnail = #False
          img = LoadImage(#PB_Any, ListFiles()\FullPath)
          If img 
            ResizeImage(img, ThumbnailSize, ThumbnailSize, #PB_Image_Raw)
            ListFiles()\ThumbnailID = img : ListFiles()\HasThumbnail = #True
            PostEvent(#Event_Thumbnail_Ready, #WinMain, #ListImages, 0, i)
          EndIf
        EndIf
      EndIf : UnlockMutex(Mutex) : Delay(30)
    Next : Delay(500)
  Wend
EndProcedure

Procedure Rotate_Image_Fast(Direction.i) ; 0 = 90 L, 1 = 90 R
  Protected idx = GetGadgetState(#ListImages), img, rotImg, p.s, x, y, w, h
  If idx >= 0
    LockMutex(Mutex) : SelectElement(ListFiles(), idx) : p = ListFiles()\FullPath : UnlockMutex(Mutex)
    img = LoadImage(#PB_Any, p)
    If img
      w = ImageWidth(img) : h = ImageHeight(img)
      Dim PixelData.i(w - 1, h - 1)
      If StartDrawing(ImageOutput(img))
        For y = 0 To h - 1 : For x = 0 To w - 1 : PixelData(x, y) = Point(x, y) : Next : Next
        StopDrawing()
      EndIf
      FreeImage(img)
      rotImg = CreateImage(#PB_Any, h, w, 32)
      If rotImg
        If StartDrawing(ImageOutput(rotImg))
          For y = 0 To h - 1 : For x = 0 To w - 1
            If Direction = 1 : Plot(h - 1 - y, x, PixelData(x, y)) : Else : Plot(y, w - 1 - x, PixelData(x, y)) : EndIf
          Next : Next
          StopDrawing()
          If LCase(GetExtensionPart(p)) = "png" : SaveImage(rotImg, p, #PB_ImagePlugin_PNG)
          Else : SaveImage(rotImg, p, #PB_ImagePlugin_JPEG, 90) : EndIf
          FreeImage(rotImg)
        EndIf
      EndIf
      Scan_Directory(CurrentPath)
      SetGadgetState(#ListImages, idx)
    EndIf
  EndIf
EndProcedure

; ============================================================================
; MAIN
; ============================================================================
Define InitPath.s = ProgramParameter(0)
If InitPath = "" Or FileSize(InitPath) <> -2 : InitPath = GetCurrentDirectory() : EndIf
If Right(InitPath, 1) <> #PS$ : InitPath + #PS$ : EndIf

If OpenWindow(#WinMain, 50, 50, 1100, 750, "PureImage Browser", #PB_Window_SystemMenu | #PB_Window_SizeGadget)
  ButtonGadget(#BtnRotateLeft, 5, 5, 70, 35, "<- 90°")
  ButtonGadget(#BtnRotateRight, 80, 5, 70, 35, "90° ->")
  ButtonGadget(#BtnRename, 155, 5, 80, 35, "Rename")
  ButtonGadget(#BtnDelete, 240, 5, 80, 35, "Delete")
  ButtonGadget(#BtnSlideshow, 325, 5, 100, 35, "Slideshow")

  ExplorerTreeGadget(#TreeDir, 5, 45, 250, 700, InitPath, #PB_Explorer_NoFiles)
  ListIconGadget(#ListImages, 260, 45, 835, 700, "Vorschau", 80, #PB_ListIcon_FullRowSelect) : AddGadgetColumn(#ListImages, 1, "Name", 400)
  
  AddKeyboardShortcut(#WinMain, #PB_Shortcut_F11, #Shortcut_F11)
  Scan_Directory(InitPath)
  Define hThread = CreateThread(@Background_Thumbnail_Worker(), 0)

  Define event, evWin, idx, item, p.s, oldName.s, newName.s, tImg
  Repeat
    event = WaitWindowEvent() : evWin = EventWindow()
    Select event
      Case #Event_Update_Image
        idx = GetGadgetState(#ListImages)
        If idx >= 0
          LockMutex(Mutex) : If idx < ListSize(ListFiles()) : SelectElement(ListFiles(), idx) : p = ListFiles()\FullPath : EndIf : UnlockMutex(Mutex)
          If Not IsWindow(#WinPreview) : Open_Preview_Window(#False) : Else : Draw_Image_To_Canvas(p) : EndIf
        EndIf

      Case #Event_Thumbnail_Ready
        idx = EventData() : LockMutex(Mutex)
        If idx < ListSize(ListFiles()) : SelectElement(ListFiles(), idx) : tImg = ListFiles()\ThumbnailID
          If IsImage(tImg) : SetGadgetItemImage(#ListImages, idx, ImageID(tImg)) : EndIf
        EndIf : UnlockMutex(Mutex)

      Case #PB_Event_Gadget
        Select EventGadget()
          Case #ListImages
            If EventType() = #PB_EventType_Change Or EventType() = #PB_EventType_LeftClick : PostEvent(#Event_Update_Image)
            ElseIf EventType() = #PB_EventType_LeftDoubleClick : Open_Preview_Window(#True) : EndIf
          Case #TreeDir 
            If EventType() = #PB_EventType_Change 
              Define newTreePath.s = GetGadgetText(#TreeDir)
              If Right(newTreePath, 1) <> #PS$ : newTreePath + #PS$ : EndIf
              Scan_Directory(newTreePath) 
            EndIf
          Case #BtnRotateLeft : Rotate_Image_Fast(0)
          Case #BtnRotateRight : Rotate_Image_Fast(1)
          Case #BtnDelete
            idx = GetGadgetState(#ListImages)
            If idx >= 0
              LockMutex(Mutex) : SelectElement(ListFiles(), idx) : p = ListFiles()\FullPath : UnlockMutex(Mutex)
              If MessageRequester("Löschen", "Datei löschen?" + #LF$ + p, #PB_MessageRequester_YesNo) = #PB_MessageRequester_Yes
                If DeleteFile(p) : Scan_Directory(CurrentPath) : EndIf
              EndIf
            EndIf
          Case #BtnRename
            idx = GetGadgetState(#ListImages)
            If idx >= 0
              LockMutex(Mutex) : SelectElement(ListFiles(), idx) : p = ListFiles()\FullPath : oldName = ListFiles()\FileName : UnlockMutex(Mutex)
              newName = InputRequester("Umbenennen", "Name:", oldName)
              If newName <> "" And newName <> oldName
                If RenameFile(p, CurrentPath + newName) : Scan_Directory(CurrentPath) : EndIf
              EndIf
            EndIf
          Case #BtnSlideshow 
            If IsSlideshow 
              IsSlideshow = #False : RemoveWindowTimer(#WinMain, #Timer_Slideshow) : SetGadgetText(#BtnSlideshow, "Slideshow")
            Else 
              If OpenWindow(#WinSlideshow, 0, 0, 320, 240, "Slideshow Setup", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#WinMain))
                TextGadget(#TxtPause, 10, 15, 280, 20, "Intervall (Sekunden):")
                SpinGadget(#SlidePause, 10, 35, 100, 25, 1, 60, #PB_Spin_Numeric) : SetGadgetState(#SlidePause, SlideshowInterval) : SetGadgetText(#SlidePause, Str(SlideshowInterval))
                TextGadget(#PB_Any, 10, 75, 280, 20, "Wildcard Filter (z.B. C*):")
                StringGadget(#SlideFilter, 10, 95, 280, 25, SlideshowPattern)
                CheckBoxGadget(#SlideRandom, 10, 135, 200, 25, "Zufall") : SetGadgetState(#SlideRandom, SlideshowRandom)
                ButtonGadget(#SlideStart, 10, 180, 300, 40, "START") 
              EndIf 
            EndIf
          Case #SlideStart  
            SlideshowInterval = Val(GetGadgetText(#SlidePause)) : SlideshowRandom = GetGadgetState(#SlideRandom) : SlideshowPattern = GetGadgetText(#SlideFilter)
            If SlideshowPattern = "" : SlideshowPattern = "*" : EndIf
            CloseWindow(#WinSlideshow)
            ClearList(SlideshowIndices())
            For item = 0 To ListSize(ListFiles()) - 1
              SelectElement(ListFiles(), item)
              If Match_Pattern(ListFiles()\FileName, SlideshowPattern) : AddElement(SlideshowIndices()) : SlideshowIndices() = item : EndIf
            Next
            If ListSize(SlideshowIndices()) > 0
              If SlideshowRandom : RandomizeList(SlideshowIndices()) : EndIf : FirstElement(SlideshowIndices())
              IsSlideshow = #True : SetGadgetText(#BtnSlideshow, "STOP") : AddWindowTimer(#WinMain, #Timer_Slideshow, SlideshowInterval * 1000) : Open_Preview_Window(#True)
            Else : MessageRequester("Info", "Nichts gefunden.") : EndIf
        EndSelect

      Case #PB_Event_Timer
        If EventTimer() = #Timer_Slideshow And IsSlideshow
          If NextElement(SlideshowIndices()) = 0 : FirstElement(SlideshowIndices()) : EndIf
          SetGadgetState(#ListImages, SlideshowIndices()) : PostEvent(#Event_Update_Image)
        EndIf

      Case #PB_Event_Menu
        Select EventMenu()
          Case #Shortcut_F11 : IsFullscreen = 1 - IsFullscreen : Open_Preview_Window(IsFullscreen)
          Case #Shortcut_ESC : If IsFullscreen : Open_Preview_Window(#False) : EndIf : If IsSlideshow : IsSlideshow = #False : RemoveWindowTimer(#WinMain, #Timer_Slideshow) : SetGadgetText(#BtnSlideshow, "Slideshow") : EndIf
        EndSelect

      Case #PB_Event_SizeWindow
        If evWin = #WinPreview : ResizeGadget(#CanvasPreview, 0, 0, WindowWidth(#WinPreview), WindowHeight(#WinPreview)) : PostEvent(#Event_Update_Image) : EndIf
      Case #PB_Event_CloseWindow : If evWin = #WinMain : Quit = #True : Break : Else : CloseWindow(evWin) : EndIf
    EndSelect
  Until Quit
  If IsThread(hThread) : WaitThread(hThread, 1000) : EndIf
EndIf
; IDE Options = PureBasic 6.30 (Linux - x64)
; CursorPosition = 36
; FirstLine = 10
; Folding = --
; EnableThread
; EnableXP
; DPIAware
; Executable = pictureview
; CommandLine = /home/rolf/Nextcloud/Hochzeit/