{$IFDEF FPC}
   {$MODE DELPHI}{$H+}
{$ENDIF}

{$I cef.inc}
unit uScheme;


interface

uses ceflib, Classes;

type
{$IFDEF CEF1}
  ICefCallback = ICefSchemeHandlerCallback;
  TWDAppScheme = class(TCefSchemeHandlerOwn)
{$ELSE}
  TWDAppScheme = class(TCefResourceHandlerOwn)
{$ENDIF}
  private
    FPath: string;
    FDataStream: TStream;
    FStatus: Integer;
    FStatusText: string;
    FMimeType: string;
  protected
    function ProcessRequest(const request: ICefRequest;
      const callback: ICefCallback): Boolean; override;
{$IFDEF CEF1}
    procedure GetResponseHeaders(const response: ICefResponse;
      var responseLength: Int64; var redirectUrl: ustring); override;
    function ReadResponse(DataOut: Pointer; BytesToRead: Integer;
      var BytesRead: Integer; const callback: ICefCallback): Boolean; override;
{$ELSE}
    procedure GetResponseHeaders(const response: ICefResponse;
      out responseLength: Int64; out redirectUrl: ustring); override;
    function ReadResponse(const dataOut: Pointer; bytesToRead: Integer;
      var bytesRead: Integer; const callback: ICefCallback): Boolean; override;
{$ENDIF}
  public
{$IFDEF CEF1}
    constructor Create(SyncMainThread: Boolean; const scheme: ustring;
      const browser: ICefBrowser; const request: ICefRequest); override;
{$ELSE}
    constructor Create(const browser: ICefBrowser; const frame: ICefFrame;
      const schemeName: ustring; const request: ICefRequest); override;
{$ENDIF}
    destructor Destroy; override;
  end;

var
  MZProtocolPath : string;

implementation

uses Windows, SysUtils;

function Escape(const str: ustring): string;
var
  p: PWideChar;
begin
  Result := '';
  p := PWideChar(str);
  while p^ <> #0 do
  begin
    if Ord(p^) > 255 then
      Result := Result + '\u' + IntToHex(Ord(p^), 4) else
      if (AnsiChar(p^) in ['\', '"']) then
        Result := Result + '\' + p^ else
        Result := Result + p^;
    inc(p);
  end;
end;


function HTTPDecode(const AStr: ustring): rbstring;
var
  Sp, Rp, Cp: PAnsiChar;
  src: rbstring;
begin
  src := rbstring(AStr);
  SetLength(Result, Length(src));
  Sp := PAnsiChar(src);
  Rp := PAnsiChar(Result);
  while Sp^ <> #0 do
  begin
    case Sp^ of
      '+': Rp^ := ' ';
      '%': begin
             Inc(Sp);
             if Sp^ = '%' then
               Rp^ := '%'
             else
             begin
               Cp := Sp;
               Inc(Sp);
               if (Cp^ <> #0) and (Sp^ <> #0) then
                 Rp^ := AnsiChar(StrToInt('$' + Char(Cp^) + Char(Sp^)))
               else
               begin
                 Result := '';
                 Exit;
               end;
             end;
           end;
    else
      Rp^ := Sp^;
    end;
    Inc(Rp);
    Inc(Sp);
  end;
  SetLength(Result, Rp - PAnsiChar(Result));
end;

function ParseFileUrl(const url: ustring): ustring;
label
  error;
var
  p, s: PWideChar;
  state: Integer;
  l : integer;
begin
  p := PWideChar(url);
  s := nil;
  state := 0;
  while True do
  begin
    case state of
      0: case p^ of
           ':': state := 1;
           #0: goto error;
         end;
      1: if p^ = '/' then
           state := 2 else
           goto error;
      2: if p^ = '/' then
         begin
           state := 3;
           s := p;
         end else
           goto error;
      3: case p^ of
           '/':
             begin
               p[-1] := #0;
               p^ := #0;
               state := 4;
             end;
           #0:
             goto error;
         else
           Result := string(p);
           exit;
         end;
    end;
    Inc(p);
  end;
error:
  Result := '';
end;

{ TFileScheme }

{$IFDEF CEF1}
constructor TWDAppScheme.Create(SyncMainThread: Boolean; const scheme: ustring;
      const browser: ICefBrowser; const request: ICefRequest);
{$ELSE}
constructor TWDAppScheme.Create(const browser: ICefBrowser; const frame: ICefFrame;
  const schemeName: ustring; const request: ICefRequest);
{$ENDIF}
begin
  inherited;
  FDataStream := nil;
end;

destructor TWDAppScheme.Destroy;
begin
  if FDataStream <> nil then
    FreeAndNil(FDataStream);
  inherited;
end;

{$IFDEF CEF1}
procedure TWDAppScheme.GetResponseHeaders(const response: ICefResponse;
  var responseLength: Int64; var redirectUrl: ustring);
{$ELSE}
procedure TWDAppScheme.GetResponseHeaders(const response: ICefResponse;
  out responseLength: Int64; out redirectUrl: ustring);
{$ENDIF}
begin
  response.Status := FStatus;
  response.StatusText := FStatusText;
  response.MimeType := FMimeType;
  responseLength := FDataStream.Size;
end;

function TWDAppScheme.ProcessRequest(const request: ICefRequest;
      const callback: ICefCallback): Boolean;
var
  rec: TSearchRec;
  i: Integer;
  rc: TResourceStream;
  //Ms : TMemoryStream;

  procedure OutPut(const str: string);
  {$IFDEF UNICODE}
  var
    rb: rbstring;
  {$ENDIF}
  begin
  {$IFDEF UNICODE}
    rb := rbstring(str);
    FDataStream.Write(rb[1], Length(rb))
  {$ELSE}
    FDataStream.Write(str[1], Length(str))
  {$ENDIF}
  end;

  procedure OutputUTF8(const str: string);
  var
    rb: rbstring;
  begin
  {$IFDEF UNICODE}
    rb := utf8string(str);
  {$ELSE}
    rb := UTF8Encode(str);
  {$ENDIF}
    FDataStream.Write(rb[1], Length(rb))
  end;
  function getMimeType(FileName:String):string;
  var
    Ext : String;
  begin
    Ext := copy(LowerCase(ExtractFileExt(FileName)), 2, MAXINT);
    if(Ext='html')OR(Ext='htm')then
    begin
      Result := 'text/html';
    end
    else if (Ext='js') then
    begin
      result := 'text/javascript';
    end
    else if (Ext='css') then
    begin
      result := 'text/css';
    end
    else if (Ext='text') then
    begin
      result := 'text/plain';
    end;
  end;
var
  n: Integer;
begin
  Result := True;
  if MZProtocolPath='' then
  begin
    MZProtocolPath := (GetCurrentDir)+'/';
  end;

  FPath := ParseFileUrl(Request.Url);
  //skip char ?
  n := Pos('?', FPath);
  if n > 0 then
    SetLength(FPath, n-1);
  //skip char #
  n := Pos('#', FPath);
  if n > 0 then
    SetLength(FPath, n-1);

  FPath := MZProtocolPath + FPath;

  if DirectoryExists(FPath) then
    FPath := FPath + '/index.htm';

  if FindFirst(FPath, 0, rec) = 0 then
  begin
    FStatus     := 200;
    FStatusText := 'OK';

    FMimeType := getMimeType(FPath);

    FDataStream := TMemoryStream.Create();
    TMemoryStream(FDataStream).LoadFromFile(FPath);
  end
  else begin
    FStatus     := 404;
    FStatusText := 'Not found';
    // error
    FDataStream := TMemoryStream.Create;

    OutputUTF8('<html><head><meta http-equiv="content-type" content="text/html; '+
      'charset=UTF-8"/></head><body><h1>'+ FPath+'</h1><h2>not found</h2></body></html>');
    FMimeType := 'text/html';
    FDataStream.Seek(0, soFromBeginning);
  end;

  FindClose(rec);
{$IFDEF CEF1}
  callback.HeadersAvailable;
  callback.BytesAvailable;
{$ELSE}
  callback.Cont;
{$ENDIF}
end;


{$IFDEF CEF1}
function TWDAppScheme.ReadResponse(DataOut: Pointer; BytesToRead: Integer;
      var BytesRead: Integer; const callback: ICefCallback): Boolean;
{$ELSE}
function TWDAppScheme.ReadResponse(const dataOut: Pointer; bytesToRead: Integer;
      var bytesRead: Integer; const callback: ICefCallback): Boolean;
{$ENDIF}
begin
  BytesRead := FDataStream.Read(DataOut^, BytesToRead);
  Result := True;
{$IFNDEF CEF1}
  callback.Cont;
{$ENDIF}
end;

end.
