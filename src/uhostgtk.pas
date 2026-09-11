unit uhostgtk;

{$mode objfpc}{$H+}

{ Linux GTK 2 window. Same TCalcController as macOS;
  this unit only presents a GdkPixbuf and forwards input. }

interface

procedure HostRun;

implementation

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}

uses
  SysUtils, ctypes, gtk2, gdk2, gdk2pixbuf, glib2, ucalcmodel, ucalcapp;

const
  WinW = 280;
  WinH = 430;

  GDK_Escape = $FF1B;
  GDK_BackSpace = $FF08;
  GDK_Delete = $FFFF;
  GDK_Return = $FF0D;
  GDK_KP_Enter = $FF8D;
  GDK_KP_Decimal = $FFAE;
  GDK_KP_Add = $FFAB;
  GDK_KP_Subtract = $FFAD;
  GDK_KP_Multiply = $FFAA;
  GDK_KP_Divide = $FFAF;
  GDK_KP_0 = $FFB0;

var
  Controller: TCalcController;
  MainWin: PGtkWidget;
  EventBox: PGtkWidget;
  Image: PGtkWidget;
  Pix: PGdkPixbuf;

procedure PixbufFromBuffer;
var
  Pixels: PByte;
  Row: Integer;
  Src, Dst: PByte;
  BufW: Integer;
begin
  if Pix = nil then
    Exit;
  BufW := Controller.Canvas.Width;
  Pixels := PByte(gdk_pixbuf_get_pixels(Pix));
  for Row := 0 to Controller.Canvas.Height - 1 do
  begin
    Src := Controller.Canvas.Ptr + Row * BufW * 4;
    Dst := Pixels + Row * gdk_pixbuf_get_rowstride(Pix);
    { Rowstride can be larger than width*4; copy one scanline at a time. }
    Move(Src^, Dst^, BufW * 4);
  end;
end;

procedure Present;
begin
  Controller.Render;
  PixbufFromBuffer;
  gtk_image_set_from_pixbuf(PGtkImage(Image), Pix);
end;

function WidgetToCanvas(WX, WY: Double; out CX, CY: Double): Boolean;
var
  Alloc: TGtkAllocation;
begin
  Result := False;
  CX := 0;
  CY := 0;
  gtk_widget_get_allocation(EventBox, @Alloc);
  if (Alloc.width < 1) or (Alloc.height < 1) then
    Exit;
  CX := WX / Alloc.width * Controller.Canvas.Width;
  CY := WY / Alloc.height * Controller.Canvas.Height;
  Result := True;
end;

procedure ShowAbout(Parent: PGtkWidget);
var
  Dlg: PGtkWidget;
begin
  Dlg := gtk_message_dialog_new(PGtkWindow(Parent), GTK_DIALOG_MODAL,
    GTK_MESSAGE_INFO, GTK_BUTTONS_OK, PChar(CalcAboutText));
  gtk_window_set_title(PGtkWindow(Dlg), CalcAboutTitle);
  gtk_dialog_run(PGtkDialog(Dlg));
  gtk_widget_destroy(Dlg);
end;

procedure OnQuit(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  gtk_main_quit;
end;

procedure OnAbout(Widget: PGtkWidget; Data: gpointer); cdecl;
begin
  ShowAbout(MainWin);
end;

function OnDelete(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  gtk_main_quit;
  Result := False; { False = GTK may destroy the window; we are quitting anyway }
end;

function OnButtonPress(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  CX, CY: Double;
begin
  Result := False;
  if Event^.button.button <> 1 then
    Exit;
  gtk_widget_grab_focus(Widget);
  if WidgetToCanvas(Event^.button.x, Event^.button.y, CX, CY) then
    Controller.MouseDown(CX, CY);
  Present;
  Result := True;
end;

function OnButtonRelease(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  CX, CY: Double;
begin
  Result := False;
  if Event^.button.button <> 1 then
    Exit;
  if WidgetToCanvas(Event^.button.x, Event^.button.y, CX, CY) then
    Controller.MouseUp(CX, CY)
  else
    Controller.MouseUp(-1, -1);
  Present;
  Result := True;
end;

function OnMotion(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  CX, CY: Double;
begin
  if WidgetToCanvas(Event^.motion.x, Event^.motion.y, CX, CY) then
    Controller.MouseMove(CX, CY);
  Present;
  Result := True;
end;

function OnLeave(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
begin
  Controller.MouseLeave;
  Present;
  Result := False;
end;

function EventToKey(Event: PGdkEvent): TCalcKey;
var
  KV: guint;
  Ch: Char;
begin
  Result := ckNone;
  if Event = nil then
    Exit;
  KV := Event^.key.keyval;
  case KV of
    GDK_Escape:
      Exit(ckAC);
    GDK_BackSpace, GDK_Delete:
      Exit(ckBackspace);
    GDK_Return, GDK_KP_Enter:
      Exit(ckEquals);
    GDK_KP_Decimal:
      Exit(ckDot);
    GDK_KP_Add:
      Exit(ckAdd);
    GDK_KP_Subtract:
      Exit(ckSub);
    GDK_KP_Multiply:
      Exit(ckMul);
    GDK_KP_Divide:
      Exit(ckDiv);
  end;
  if (KV >= GDK_KP_0) and (KV <= GDK_KP_0 + 9) then
    Exit(TCalcKey(Ord(ck0) + (KV - GDK_KP_0)));
  if KV <= 127 then
  begin
    Ch := Chr(KV);
    Result := CalcKeyFromChar(Ch);
  end;
end;

function OnKey(Widget: PGtkWidget; Event: PGdkEvent; Data: gpointer): gboolean; cdecl;
var
  Mapped: TCalcKey;
begin
  Mapped := EventToKey(Event);
  if Mapped = ckNone then
  begin
    Result := False;
    Exit;
  end;
  Controller.KeyPress(Mapped);
  Present;
  Result := True;
end;

function BuildMenuBar: PGtkWidget;
var
  Bar, Menu, Item: PGtkWidget;
  Root: PGtkWidget;
begin
  Bar := gtk_menu_bar_new;
  Menu := gtk_menu_new;
  Root := gtk_menu_item_new_with_label('Calculator');
  gtk_menu_item_set_submenu(PGtkMenuItem(Root), Menu);
  gtk_menu_shell_append(PGtkMenuShell(Bar), Root);

  Item := gtk_menu_item_new_with_label('About Goody''s Calculator');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnAbout), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_separator_menu_item_new;
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Item := gtk_menu_item_new_with_label('Quit');
  g_signal_connect(G_OBJECT(Item), 'activate', TG_SIGNAL_FUNC(@OnQuit), nil);
  gtk_menu_shell_append(PGtkMenuShell(Menu), Item);
  Result := Bar;
end;

procedure HostRun;
var
  Box: PGtkWidget;
  Mask: gint;
begin
  gtk_init(@argc, @argv); { GTK takes the real argv so --display still works }
  Controller := TCalcController.Create(WinW, WinH);

  Pix := gdk_pixbuf_new(GDK_COLORSPACE_RGB, True, 8,
    Controller.Canvas.Width, Controller.Canvas.Height);

  MainWin := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(PGtkWindow(MainWin), 'Goody''s Calculator');
  gtk_window_set_resizable(PGtkWindow(MainWin), False);
  gtk_window_set_default_size(PGtkWindow(MainWin), WinW, WinH);
  g_signal_connect(G_OBJECT(MainWin), 'delete-event', TG_SIGNAL_FUNC(@OnDelete), nil);
  g_signal_connect(G_OBJECT(MainWin), 'key-press-event', TG_SIGNAL_FUNC(@OnKey), nil);
  { Keys land on the window; the event box only sees the mouse. }

  Box := gtk_vbox_new(False, 0);
  gtk_container_add(PGtkContainer(MainWin), Box);
  gtk_box_pack_start(PGtkBox(Box), BuildMenuBar, False, False, 0);

  EventBox := gtk_event_box_new; { gtk_image does not receive clicks on its own }
  gtk_box_pack_start(PGtkBox(Box), EventBox, True, True, 0);
  Image := gtk_image_new;
  gtk_container_add(PGtkContainer(EventBox), Image);

  Mask := GDK_BUTTON_PRESS_MASK or GDK_BUTTON_RELEASE_MASK or
    GDK_POINTER_MOTION_MASK or GDK_LEAVE_NOTIFY_MASK;
  gtk_widget_add_events(EventBox, Mask);
  g_signal_connect(G_OBJECT(EventBox), 'button-press-event', TG_SIGNAL_FUNC(@OnButtonPress), nil);
  g_signal_connect(G_OBJECT(EventBox), 'button-release-event', TG_SIGNAL_FUNC(@OnButtonRelease), nil);
  g_signal_connect(G_OBJECT(EventBox), 'motion-notify-event', TG_SIGNAL_FUNC(@OnMotion), nil);
  g_signal_connect(G_OBJECT(EventBox), 'leave-notify-event', TG_SIGNAL_FUNC(@OnLeave), nil);

  gtk_widget_set_can_focus(EventBox, True);
  Present; { first paint before gtk_main so the window is not blank }
  gtk_widget_show_all(MainWin);
  gtk_widget_grab_focus(EventBox);
  gtk_main;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
