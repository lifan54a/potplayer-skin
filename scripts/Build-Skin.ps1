[CmdletBinding()]
param(
    [ValidatePattern('^#[0-9A-Fa-f]{6}$')][string]$AccentColor = '#BCC5CF',
    [ValidatePattern('^#[0-9A-Fa-f]{6}$')][string]$BackgroundColor = '#191B1F',
    [string]$OutputFile = '',
    [string]$ThemeName = '铂金灰'
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot
$sourceRoot=Join-Path $projectRoot 'src'
if(-not $OutputFile){$OutputFile=Join-Path $projectRoot "dist\Sailor优化版_$ThemeName.dsf"}
$OutputFile=[IO.Path]::GetFullPath($OutputFile)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(-not ('SailorSkin.Palette' -as [type])){
$runtimeDirectory=Split-Path ([object].Assembly.Location)
$drawingReferences=@([Drawing.Bitmap].Assembly.Location,[Drawing.Color].Assembly.Location,(Join-Path $runtimeDirectory 'System.Runtime.dll'),(Join-Path $runtimeDirectory 'System.Runtime.InteropServices.dll'),(Join-Path $runtimeDirectory 'System.ComponentModel.Primitives.dll'))
foreach($dependency in [Drawing.Bitmap].Assembly.GetReferencedAssemblies()){
 if($dependency.Name -like 'System.Private.Windows.*'){
  $drawingReferences+=([Reflection.Assembly]::Load($dependency)).Location
 }
}
Add-Type -ReferencedAssemblies $drawingReferences -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
namespace SailorSkin {
 public static class Palette {
  public static void Apply(string input,string output,Color accent,Color background) {
   // Edit decoded pixels in place. Drawing onto a new 96 DPI bitmap changes
   // the atlas geometry when the input has a different physical resolution.
   // Skin layouts address these pixels directly; their coordinates must stay fixed.
   using(var bitmap=new Bitmap(input)) {
    var data=bitmap.LockBits(new Rectangle(0,0,bitmap.Width,bitmap.Height),ImageLockMode.ReadWrite,PixelFormat.Format32bppArgb);
    try {
     var row=new byte[bitmap.Width*4];
     for(int y=0;y<bitmap.Height;y++){
      var ptr=IntPtr.Add(data.Scan0,y*data.Stride); Marshal.Copy(ptr,row,0,row.Length);
      for(int x=0;x<row.Length;x+=4){
       int b=row[x],g=row[x+1],r=row[x+2]; if(row[x+3]==0)continue;
       if(b>r+45 && g>r+25 && b>g+20){
        double strength=(b-r)/255.0;
        row[x]=(byte)Math.Min(255,r+accent.B*strength);
        row[x+1]=(byte)Math.Min(255,r+accent.G*strength);
        row[x+2]=(byte)Math.Min(255,r+accent.R*strength);
       }else if(r==24 && g==25 && b==26){
        row[x]=background.B; row[x+1]=background.G; row[x+2]=background.R;
       }
      }
      Marshal.Copy(row,0,ptr,row.Length);
     }
    }finally{bitmap.UnlockBits(data);}
    bitmap.Save(output,ImageFormat.Png);
   }
  }
  public static void ValidateGeometry(string input,string output) {
   using(var original=new Bitmap(input))
   using(var result=new Bitmap(output)) {
    if(original.Width!=result.Width || original.Height!=result.Height)
     throw new InvalidOperationException("Atlas dimensions changed: "+input);
    if(Math.Abs(original.HorizontalResolution-result.HorizontalResolution)>.1 ||
       Math.Abs(original.VerticalResolution-result.VerticalResolution)>.1)
     throw new InvalidOperationException("Atlas DPI changed: "+input);
    for(int y=0;y<original.Height;y++)for(int x=0;x<original.Width;x++){
     var before=original.GetPixel(x,y);var after=result.GetPixel(x,y);
     if(before.A!=after.A)
      throw new InvalidOperationException("Atlas transparency moved at "+x+","+y+": "+input);
     bool isAccent=before.B>before.R+45 && before.G>before.R+25 && before.B>before.G+20;
     bool isBackground=before.R==24 && before.G==25 && before.B==26;
     if(!isAccent && !isBackground && before.ToArgb()!=after.ToArgb())
      throw new InvalidOperationException("Untargeted atlas pixel changed at "+x+","+y+": "+input);
    }
   }
  }
 }
}
'@
}
$buildRoot=Join-Path $projectRoot ('.build\'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $buildRoot -Force
$accent=[Drawing.ColorTranslator]::FromHtml($AccentColor)
$background=[Drawing.ColorTranslator]::FromHtml($BackgroundColor)
foreach($png in Get-ChildItem -LiteralPath $sourceRoot -Filter '*.png'){
 $outputPng=Join-Path $buildRoot $png.Name
 [SailorSkin.Palette]::Apply($png.FullName,$outputPng,$accent,$background)
 [SailorSkin.Palette]::ValidateGeometry($png.FullName,$outputPng)
}
$hex=$AccentColor.TrimStart('#').ToUpperInvariant()
$pressed='{0:X2}{1:X2}{2:X2}' -f [int]($accent.R*.8),[int]($accent.G*.8),[int]($accent.B*.8)
foreach($name in @('VideoSkin.xml','AudioSkin.xml')){
 $path=Join-Path $buildRoot $name
 $text=[IO.File]::ReadAllText($path).Replace('0x0099FF',('0x'+$hex)).Replace('0x007ACC',('0x'+$pressed))
 [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($true))
}
Add-Content -LiteralPath (Join-Path $buildRoot 'Title.txt') -Value "主题：$ThemeName`r`n强调色：$AccentColor`r`n背景色：$BackgroundColor" -Encoding utf8
& (Join-Path $PSScriptRoot 'Validate-Skin.ps1') -SourceRoot $buildRoot
New-Item -ItemType Directory -Path (Split-Path $OutputFile) -Force | Out-Null
# Create a stable archive with root-level skin entries and no enclosing folder.
$fileStream=[IO.File]::Open($OutputFile,[IO.FileMode]::Create)
$archive=[IO.Compression.ZipArchive]::new($fileStream,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($file in Get-ChildItem -LiteralPath $buildRoot -File | Sort-Object Name){
  $entry=$archive.CreateEntry($file.Name,[IO.Compression.CompressionLevel]::Optimal)
  $entry.LastWriteTime=[DateTimeOffset]::new(2026,11,4,0,0,0,[TimeSpan]::Zero)
  $stream=$entry.Open();$bytes=[IO.File]::ReadAllBytes($file.FullName)
  try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
 }
}finally{$archive.Dispose();$fileStream.Dispose()}
$check=[IO.Compression.ZipFile]::OpenRead($OutputFile)
try{
 foreach($entry in $check.Entries){
  $stream=$entry.Open();$memory=[IO.MemoryStream]::new()
  try{$stream.CopyTo($memory)}finally{$stream.Dispose();$memory.Dispose()}
 }
}finally{$check.Dispose()}
# Remove only this invocation's generated workspace, after checking containment.
$buildParent=[IO.Path]::GetFullPath((Join-Path $projectRoot '.build'))+[IO.Path]::DirectorySeparatorChar
if(-not [IO.Path]::GetFullPath($buildRoot).StartsWith($buildParent,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected build path'}
Remove-Item -LiteralPath $buildRoot -Recurse -Force
Write-Host "Built $OutputFile"
Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256
