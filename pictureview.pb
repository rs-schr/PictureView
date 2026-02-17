EnableExplicit

; Plugins für plattformübergreifende Bildunterstützung
UseJPEGImageDecoder() : UseJPEGImageEncoder()
UsePNGImageDecoder() : UsePNGImageEncoder()
UseGIFImageDecoder()

; ============================================================================
; KONSTANTEN & STRUKTUREN
; ============================================================================
Enumeration Windows
    #WinMain
    #WinPreview
    #WinSlideshow
EndEnumeration

Enumeration Gadgets
    #TreeDir
    #ListImages
    #CanvasPreview
    #BtnRotateLeft
    #BtnRotateRight
    #BtnRename
    #BtnDelete
    #BtnCopy
    #BtnMove
    #BtnSlideshow
    #SlidePaus
    #SlideRandom
    #SlideStart
    #SlidePause    
    #TxtPause
    #SlideFilter
    #WinSelectDir
    #TreeSelectDir
    #BtnSelectDirOK
    #BtnSelectDirCancel
EndEnumeration

Enumeration Shortcuts
    #Shortcut_F11
    #Shortcut_ESC
EndEnumeration

#Timer_Slideshow = 1
#Event_Thumbnail_Ready = #PB_Event_FirstCustomValue
#Event_Update_Image    = #PB_Event_FirstCustomValue + 1

Structure ImageEntry
    fileName.s
    fullPath.s
    hasThumbnail.b
    thumbnailID.i
EndStructure

Global NewList listFiles.ImageEntry(), NewList slideshowIndices.i()
Global currentPath.s, isFullscreen.b = #False, isSlideshow.b = #False
Global slideshowInterval.i = 3, slideshowRandom.b = #False, slideshowPattern.s = "*"
Global prevX = 100, prevY = 100, prevW = 800, prevH = 600
Global thumbnailSize = 64, mutex.i = CreateMutex(), quit.b = #False
Global darkMode = #True

; ============================================================================
; HILFSFUNKTIONEN
; ============================================================================

Procedure.s SelectDirectoryDialog(title.s, initialPath.s)
    Protected result.s = ""
    Protected selectedPath.s = initialPath
    Protected ev.l
    
    If OpenWindow(#WinSelectDir, 0, 0, 400, 450, title, #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#WinMain))
        ExplorerTreeGadget(#TreeSelectDir, 10, 10, 380, 380, initialPath, #PB_Explorer_NoFiles)
        ButtonGadget(#BtnSelectDirOK, 10, 420, 180, 25, "Ausw�hlen")
        ButtonGadget(#BtnSelectDirCancel, 210, 420, 180, 25, "Abbrechen")
        
        SetGadgetState(#TreeSelectDir, GetGadgetItemState(#TreeSelectDir, -1))
        
        Repeat
            ev = WaitWindowEvent()
            
            If ev = #PB_Event_Gadget
                Select EventGadget()
                    Case #TreeSelectDir
                        If GetGadgetState(#TreeSelectDir) >= 0
                            selectedPath = GetGadgetText(#TreeSelectDir)
                        EndIf
                    Case #BtnSelectDirOK
                        result = selectedPath
                        Break
                    Case #BtnSelectDirCancel
                        result = ""
                        Break
                EndSelect
            EndIf
        Until ev = #PB_Event_CloseWindow
        
        CloseWindow(#WinSelectDir)
    EndIf
    
    ProcedureReturn result
EndProcedure

Procedure.b match_pattern(string.s, pattern.s)
    Protected regex = CreateRegularExpression(#PB_Any, "^" + ReplaceString(ReplaceString(Pattern, ".", "\."), "*", ".*") + "$", #PB_RegularExpression_NoCase)
    Protected result.b = #False
    If regex
        If MatchRegularExpression(regex, string)
            result = #True
        EndIf
        FreeRegularExpression(regex)
    EndIf
    ProcedureReturn result
EndProcedure

Procedure draw_image_to_canvas(imagePath.s)
    Protected img, canvasW, canvasH, thumbW, thumbH, factor.f
    If IsGadget(#CanvasPreview) And FileSize(imagePath) > 0
        img = LoadImage(#PB_Any, imagePath)
        If img
            canvasW = GadgetWidth(#CanvasPreview)
            canvasH = GadgetHeight(#CanvasPreview)
            If canvasW > 10 And canvasH > 10
                factor = canvasW / ImageWidth(img)
                If (ImageHeight(img) * factor) > canvasH
                    factor = canvasH / ImageHeight(img)
                EndIf
                thumbW = ImageWidth(img) * factor
                thumbH = ImageHeight(img) * factor
                If StartDrawing(CanvasOutput(#CanvasPreview))
                    If darkMode
                        Box(0, 0, canvasW, canvasH, RGB(30, 30, 30))
                    Else
                        Box(0, 0, canvasW, canvasH, RGB(200, 200, 200))
                    EndIf
                    DrawImage(ImageID(img), (canvasW - thumbW) / 2, (canvasH - thumbH) / 2, thumbW, thumbH)
                    StopDrawing()
                EndIf
            EndIf
            FreeImage(img)
        EndIf
    EndIf
EndProcedure

Procedure open_preview_window(fullscreen.b)
    If IsWindow(#WinPreview)
        CloseWindow(#WinPreview)
    EndIf
    ExamineDesktops()
    If fullscreen
        OpenWindow(#WinPreview, 0, 0, DesktopWidth(0), DesktopHeight(0), "", #PB_Window_BorderLess)
        isFullscreen = #True
    Else
        OpenWindow(#WinPreview, prevX, prevY, prevW, prevH, "Vorschau", #PB_Window_SystemMenu | #PB_Window_SizeGadget)
        isFullscreen = #False
    EndIf
    CanvasGadget(#CanvasPreview, 0, 0, WindowWidth(#WinPreview), WindowHeight(#WinPreview))
    AddKeyboardShortcut(#WinPreview, #PB_Shortcut_F11, #Shortcut_F11)
    AddKeyboardShortcut(#WinPreview, #PB_Shortcut_Escape, #Shortcut_ESC)
    PostEvent(#Event_Update_Image)
EndProcedure

Procedure scan_directory(path.s)
    Protected dir, ext.s
    If path = ""
        ProcedureReturn
    EndIf
    If Right(path, 1) <> #PS$
        path + #PS$
    EndIf
    currentPath = path
    dir = ExamineDirectory(#PB_Any, path, "*.*")
    LockMutex(mutex)
    ForEach listFiles()
        If IsImage(listFiles()\thumbnailID)
            FreeImage(listFiles()\thumbnailID)
        EndIf
    Next
    ClearList(listFiles())
    ClearGadgetItems(#ListImages)
    If dir
        While NextDirectoryEntry(dir)
            If DirectoryEntryType(dir) = #PB_DirectoryEntry_File
                ext = LCase(GetExtensionPart(DirectoryEntryName(dir)))
                If ext = "jpg" Or ext = "jpeg" Or ext = "png" Or ext = "gif"
                    AddElement(listFiles())
                    listFiles()\fileName = DirectoryEntryName(dir)
                    listFiles()\fullPath = path + listFiles()\fileName
                    listFiles()\hasThumbnail = #False
                    listFiles()\thumbnailID = 0
                EndIf
            EndIf
        Wend
        FinishDirectory(dir)
        SortStructuredList(listFiles(), #PB_Sort_Ascending | #PB_Sort_NoCase, OffsetOf(ImageEntry\fileName), TypeOf(ImageEntry\fileName))
        ForEach listFiles()
            AddGadgetItem(#ListImages, -1, Chr(10) + listFiles()\fileName)
        Next
    EndIf
    UnlockMutex(mutex)
    If ListSize(listFiles()) > 0
        SetGadgetState(#ListImages, 0)
        PostEvent(#Event_Update_Image)
    EndIf
EndProcedure

Procedure background_thumbnail_worker(threadID.i)
    Protected img, index, total
    While Not quit
        LockMutex(mutex)
        total = ListSize(listFiles())
        UnlockMutex(mutex)
        For index = 0 To total - 1
            If quit
                Break
            EndIf
            LockMutex(mutex)
            If index < ListSize(listFiles())
                SelectElement(listFiles(), index)
                If listFiles()\hasThumbnail = #False
                    img = LoadImage(#PB_Any, listFiles()\fullPath)
                    If img
                        ResizeImage(img, thumbnailSize, thumbnailSize, #PB_Image_Raw)
                        listFiles()\thumbnailID = img
                        listFiles()\hasThumbnail = #True
                        PostEvent(#Event_Thumbnail_Ready, #WinMain, #ListImages, 0, index)
                    EndIf
                EndIf
            EndIf
            UnlockMutex(mutex)
            Delay(30)
        Next
        Delay(500)
    Wend
EndProcedure

Procedure rotate_image_fast(direction.i)
    Protected idx = GetGadgetState(#ListImages), img, rotImg, path.s, x, y, imgW, imgH
    If idx >= 0
        LockMutex(mutex)
        SelectElement(listFiles(), idx)
        path = listFiles()\fullPath
        UnlockMutex(mutex)
        If FileSize(path) <= 0
            ProcedureReturn
        EndIf
        img = LoadImage(#PB_Any, path)
        If img
            imgW = ImageWidth(img)
            imgH = ImageHeight(img)
            Dim pixelData.i(imgW - 1, imgH - 1)
            If StartDrawing(ImageOutput(img))
                For y = 0 To imgH - 1
                    For x = 0 To imgW - 1
                        pixelData(x, y) = Point(x, y)
                    Next
                Next
                StopDrawing()
            EndIf
            FreeImage(img)
            rotImg = CreateImage(#PB_Any, imgH, imgW, 32)
            If rotImg
                If StartDrawing(ImageOutput(rotImg))
                    For y = 0 To imgH - 1
                        For x = 0 To imgW - 1
                            If direction = 1
                                Plot(imgH - 1 - y, x, pixelData(x, y))
                            Else
                                Plot(y, imgW - 1 - x, pixelData(x, y))
                            EndIf
                        Next
                    Next
                    StopDrawing()
                    If LCase(GetExtensionPart(path)) = "png"
                        SaveImage(rotImg, path, #PB_ImagePlugin_PNG)
                    Else
                        SaveImage(rotImg, path, #PB_ImagePlugin_JPEG, 90)
                    EndIf
                    FreeImage(rotImg)
                EndIf
            EndIf
            scan_directory(currentPath)
            SetGadgetState(#ListImages, idx)
        EndIf
    EndIf
EndProcedure

Procedure copy_file(src.s, dest.s)
    Protected result = #False
    If FileSize(src) > 0
        If CopyFile(src, dest)
            result = #True
        EndIf
    EndIf
    ProcedureReturn result
EndProcedure

Procedure move_file(src.s, dest.s)
    Protected result = #False
    If FileSize(src) > 0
        If RenameFile(src, dest)
            result = #True
        Else
            If CopyFile(src, dest)
                If DeleteFile(src)
                    result = #True
                EndIf
            EndIf
        EndIf
    EndIf
    ProcedureReturn result
EndProcedure

; ============================================================================
; MAIN
; ============================================================================
Define initPath.s = ProgramParameter(0)
If initPath = "" Or FileSize(initPath) <> -2
    initPath = GetCurrentDirectory()
EndIf
If Right(initPath, 1) <> #PS$
    initPath + #PS$
EndIf

If OpenWindow(#WinMain, 50, 50, 1100, 750, "PictureView", #PB_Window_SystemMenu | #PB_Window_SizeGadget)
    ButtonGadget(#BtnRotateLeft, 5, 5, 70, 35, "<- 90°")
    ButtonGadget(#BtnRotateRight, 80, 5, 70, 35, "90° ->")
    ButtonGadget(#BtnRename, 155, 5, 80, 35, "Rename")
    ButtonGadget(#BtnDelete, 240, 5, 80, 35, "Delete")
    ButtonGadget(#BtnCopy, 325, 5, 80, 35, "Copy")
    ButtonGadget(#BtnMove, 410, 5, 80, 35, "Move")
    ButtonGadget(#BtnSlideshow, 495, 5, 100, 35, "Slideshow")

    ExplorerTreeGadget(#TreeDir, 5, 45, 250, 700, initPath, #PB_Explorer_NoFiles)
    ListIconGadget(#ListImages, 260, 45, 835, 700, "Vorschau", 80, #PB_ListIcon_FullRowSelect)
    AddGadgetColumn(#ListImages, 1, "Name", 400)

    AddKeyboardShortcut(#WinMain, #PB_Shortcut_F11, #Shortcut_F11)
    scan_directory(initPath)
    Define thumbnailThread = CreateThread(@background_thumbnail_worker(), 0)

    Define event, evWin, idx, item, filePath.s, oldName.s, newName.s, thumbImg
    Repeat
        event = WaitWindowEvent()
        evWin = EventWindow()
        Select event
            Case #Event_Update_Image
                idx = GetGadgetState(#ListImages)
                If idx >= 0
                    LockMutex(mutex)
                    If idx < ListSize(listFiles())
                        SelectElement(listFiles(), idx)
                        filePath = listFiles()\fullPath
                    EndIf
                    UnlockMutex(mutex)
                    If Not IsWindow(#WinPreview)
                        open_preview_window(#False)
                    Else
                        draw_image_to_canvas(filePath)
                    EndIf
                EndIf

            Case #Event_Thumbnail_Ready
                idx = EventData()
                LockMutex(mutex)
                If idx < ListSize(listFiles())
                    SelectElement(listFiles(), idx)
                    thumbImg = listFiles()\thumbnailID
                    If IsImage(thumbImg)
                        SetGadgetItemImage(#ListImages, idx, ImageID(thumbImg))
                    EndIf
                EndIf
                UnlockMutex(mutex)

            Case #PB_Event_Gadget
                Select EventGadget()
                    Case #ListImages
                        If EventType() = #PB_EventType_Change Or EventType() = #PB_EventType_LeftClick
                            PostEvent(#Event_Update_Image)
                        ElseIf EventType() = #PB_EventType_LeftDoubleClick
                            open_preview_window(#True)
                        EndIf
                    Case #TreeDir
                        If EventType() = #PB_EventType_Change
                            Define newTreePath.s = GetGadgetText(#TreeDir)
                            If Right(newTreePath, 1) <> #PS$
                                newTreePath + #PS$
                            EndIf
                            scan_directory(newTreePath)
                        EndIf
                    Case #BtnRotateLeft
                        rotate_image_fast(0)
                    Case #BtnRotateRight
                        rotate_image_fast(1)
                    Case #BtnDelete
                        idx = GetGadgetState(#ListImages)
                        If idx >= 0
                            LockMutex(mutex)
                            SelectElement(listFiles(), idx)
                            filePath = listFiles()\fullPath
                            UnlockMutex(mutex)
                            If MessageRequester("Löschen", "Datei löschen?" + #LF$ + filePath, #PB_MessageRequester_YesNo) = #PB_MessageRequester_Yes
                                If DeleteFile(filePath)
                                    scan_directory(currentPath)
                                EndIf
                            EndIf
                        EndIf
                    Case #BtnRename
                        idx = GetGadgetState(#ListImages)
                        If idx >= 0
                            LockMutex(mutex)
                            SelectElement(listFiles(), idx)
                            filePath = listFiles()\fullPath
                            oldName = listFiles()\fileName
                            UnlockMutex(mutex)
                            newName = InputRequester("Umbenennen", "Name:", oldName)
                            If newName <> "" And newName <> oldName
                                If RenameFile(filePath, currentPath + newName)
                                    scan_directory(currentPath)
                                EndIf
                            EndIf
                        EndIf
                    Case #BtnCopy
                        idx = GetGadgetState(#ListImages)
                        If idx >= 0
                            LockMutex(mutex)
                            SelectElement(listFiles(), idx)
                            filePath = listFiles()\fullPath
                            UnlockMutex(mutex)
                            newName = SelectDirectoryDialog("Kopieren nach...", currentPath)
                            If newName <> ""
                                Define destPath.s = newName + #PS$ + GetFilePart(filePath)
                                If copy_file(filePath, destPath)
                                    MessageRequester("Erfolg", "Datei kopiert.")
                                    scan_directory(currentPath)
                                Else
                                    MessageRequester("Fehler", "Kopieren fehlgeschlagen.")
                                EndIf
                            EndIf
                        EndIf
                    Case #BtnMove
                        idx = GetGadgetState(#ListImages)
                        If idx >= 0
                            LockMutex(mutex)
                            SelectElement(listFiles(), idx)
                            filePath = listFiles()\fullPath
                            UnlockMutex(mutex)
                            newName = SelectDirectoryDialog("Verschieben nach...", currentPath)
                            If newName <> ""
                                Define moveDest.s = newName + #PS$ + GetFilePart(filePath)
                                If move_file(filePath, moveDest)
                                    MessageRequester("Erfolg", "Datei verschoben.")
                                    scan_directory(currentPath)
                                Else
                                    MessageRequester("Fehler", "Verschieben fehlgeschlagen.")
                                EndIf
                            EndIf
                        EndIf
                    Case #BtnSlideshow
                        If isSlideshow
                            isSlideshow = #False
                            RemoveWindowTimer(#WinMain, #Timer_Slideshow)
                            SetGadgetText(#BtnSlideshow, "Slideshow")
                        Else
                            If OpenWindow(#WinSlideshow, 0, 0, 320, 240, "Slideshow Setup", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(#WinMain))
                                TextGadget(#TxtPause, 10, 15, 280, 20, "Intervall (Sekunden):")
                                SpinGadget(#SlidePause, 10, 35, 100, 25, 1, 60, #PB_Spin_Numeric)
                                SetGadgetState(#SlidePause, slideshowInterval)
                                SetGadgetText(#SlidePause, Str(slideshowInterval))
                                TextGadget(#PB_Any, 10, 75, 280, 20, "Wildcard Filter (z.B. C*):")
                                StringGadget(#SlideFilter, 10, 95, 280, 25, slideshowPattern)
                                CheckBoxGadget(#SlideRandom, 10, 135, 200, 25, "Zufall")
                                SetGadgetState(#SlideRandom, slideshowRandom)
                                ButtonGadget(#SlideStart, 10, 180, 300, 40, "START")
                            EndIf
                        EndIf
                    Case #SlideStart
                        slideshowInterval = Val(GetGadgetText(#SlidePause))
                        slideshowRandom = GetGadgetState(#SlideRandom)
                        slideshowPattern = GetGadgetText(#SlideFilter)
                        If slideshowPattern = ""
                            slideshowPattern = "*"
                        EndIf
                        CloseWindow(#WinSlideshow)
                        ClearList(slideshowIndices())
                        For item = 0 To ListSize(listFiles()) - 1
                            SelectElement(listFiles(), item)
                            If match_pattern(listFiles()\fileName, slideshowPattern)
                                AddElement(slideshowIndices())
                                slideshowIndices() = item
                            EndIf
                        Next
                        If ListSize(slideshowIndices()) > 0
                            If slideshowRandom
                                RandomizeList(slideshowIndices())
                            EndIf
                            FirstElement(slideshowIndices())
                            isSlideshow = #True
                            SetGadgetText(#BtnSlideshow, "STOP")
                            AddWindowTimer(#WinMain, #Timer_Slideshow, slideshowInterval * 1000)
                            open_preview_window(#True)
                        Else
                            MessageRequester("Info", "Nichts gefunden.")
                        EndIf
                EndSelect

            Case #PB_Event_Timer
                If EventTimer() = #Timer_Slideshow And isSlideshow
                    If NextElement(slideshowIndices()) = 0
                        FirstElement(slideshowIndices())
                    EndIf
                    SetGadgetState(#ListImages, slideshowIndices())
                    PostEvent(#Event_Update_Image)
                EndIf

            Case #PB_Event_Menu
                Select EventMenu()
                    Case #Shortcut_F11
                        If isFullscreen = #False
                            If IsWindow(#WinPreview)
                                prevX = WindowX(#WinPreview)
                                prevY = WindowY(#WinPreview)
                                prevW = WindowWidth(#WinPreview)
                                prevH = WindowHeight(#WinPreview)
                            EndIf
                        EndIf
                        isFullscreen = 1 - isFullscreen
                        open_preview_window(isFullscreen)
                    Case #Shortcut_ESC
                        If isFullscreen
                            open_preview_window(#False)
                        EndIf
                        If isSlideshow
                            isSlideshow = #False
                            RemoveWindowTimer(#WinMain, #Timer_Slideshow)
                            SetGadgetText(#BtnSlideshow, "Slideshow")
                        EndIf
                EndSelect

            Case #PB_Event_SizeWindow
                If evWin = #WinPreview
                    ResizeGadget(#CanvasPreview, 0, 0, WindowWidth(#WinPreview), WindowHeight(#WinPreview))
                    PostEvent(#Event_Update_Image)
                EndIf
            Case #PB_Event_CloseWindow
                If evWin = #WinMain
                    quit = #True
                    Break
                Else
                    CloseWindow(evWin)
                EndIf
        EndSelect
    Until quit
    If IsThread(thumbnailThread)
        WaitThread(thumbnailThread, 1000)
    EndIf
EndIf
; IDE Options = PureBasic 6.30 (Linux - x64)
; CursorPosition = 51
; FirstLine = 26
; Folding = --
; EnableThread
; EnableXP
; DPIAware
; Executable = pictureview
; CommandLine = /home/rolf/Nextcloud/Hochzeit/