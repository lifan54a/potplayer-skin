param([string]$SourceRoot=(Join-Path (Split-Path $PSScriptRoot) 'src'))
$ErrorActionPreference='Stop'
if(-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'VideoSkin.xml'))){throw 'Missing VideoSkin.xml'}
foreach($file in Get-ChildItem -LiteralPath $SourceRoot -File | Where-Object Extension -in '.xml','.txt'){
 $text=[IO.File]::ReadAllText($file.FullName)
 foreach($reference in [regex]::Matches($text,'#include<([^>]+)>|\bImage\s*=\s*["'']([^"'']+)["'']')){
  $name=if($reference.Groups[1].Success){$reference.Groups[1].Value}else{$reference.Groups[2].Value}
  if(-not (Test-Path -LiteralPath (Join-Path $SourceRoot $name))){throw "Missing reference $name in $($file.Name)"}
 }
}
foreach($name in @('VideoSkin.xml','AudioSkin.xml')){
 $text=[IO.File]::ReadAllText((Join-Path $SourceRoot $name))
 $text=[regex]::Replace($text,'(?s)<!--.*?-->','')
 $text=[regex]::Replace($text,'(?m)^\s*#.*$','')
 $stack=[Collections.Generic.Stack[string]]::new()
 foreach($tag in [regex]::Matches($text,'</?([A-Za-z][A-Za-z0-9]*)\b[^>]*>')){
  if($tag.Value.StartsWith('</')){
   if($stack.Count -eq 0 -or $stack.Pop() -ne $tag.Groups[1].Value){throw "Unbalanced layout in $name at $($tag.Value)"}
  }elseif(-not $tag.Value.EndsWith('/>')){$stack.Push($tag.Groups[1].Value)}
 }
 if($stack.Count -ne 0){throw "Unclosed layout in $name"}
 foreach($command in @('ID_PLAY_SPEED_SLOWER','ID_PLAY_SPEED_NORMAL','ID_PLAY_SPEED_FASTER','CMD_PLAY_SPEED_MESSAGE')){
  if(-not $text.Contains($command)){throw "Missing speed command $command"}
 }
 if([regex]::Matches($text,'<Static Align="Bottom" Height="65"').Count -ne 2){throw "Unexpected footer dimensions in $name"}
 if([regex]::Matches($text,'speed-group:').Count -ne 0){throw 'Unexpected unstripped comment'}
 # Validate the actual transport branches, rather than assumed seek-row coordinates.
 $raw=[IO.File]::ReadAllText((Join-Path $SourceRoot $name))
 $footers=[regex]::Matches($raw,'(?s)<!-- responsive-footer:.*?(?=\s*<Static Align="Client" Contain="CMD_VIDEO_WINDOW"|\s*<Static Align="Bottom" Height="240")')
 if($footers.Count -ne 2){throw "Could not isolate responsive footers in $name"}
 foreach($footerMatch in $footers){
  $fragment=$footerMatch.Value
  # Match only the balanced outer footer; audio layouts can have following content.
  $first=[regex]::Match($fragment,'<Static\b[^>]*>');$depth=1;$end=$null
  foreach($token in [regex]::Matches($fragment.Substring($first.Index+$first.Length),'</?Static\b[^>]*>')){
   if($token.Value.StartsWith('</')){$depth--}elseif(-not $token.Value.EndsWith('/>')){$depth++}
   if($depth -eq 0){$end=$first.Index+$first.Length+$token.Index+$token.Length;break}
  }
  if($null -eq $end){throw 'Cannot find footer end'}
  $footerXml=[xml]$fragment.Substring($first.Index,$end-$first.Index)
  $transport=$footerXml.Static.SelectSingleNode('./Static[@Align="Bottom"]')
  if([int]$transport.Height -ne 44){throw 'Transport row needs a 44 px reserved area'}
  foreach($width in @(240,246,250,300,349,350,351,419,420,519,520,521,699,700,701,960,1216,1920)){
   $activeBranches=@($transport.SelectNodes('./Static') | Where-Object {
    (-not $_.HasAttribute('VisParentMinWidth') -or $width -gt [int]$_.VisParentMinWidth) -and
    (-not $_.HasAttribute('VisParentMaxWidth') -or $width -lt [int]$_.VisParentMaxWidth)
   })
   if($activeBranches.Count -ne 1){throw "Expected one transport branch at width $width"}
   $rectangles=[Collections.Generic.List[object]]::new()
   function Read-Controls($parent,[double]$parentWidth,[double]$offsetX,[double]$offsetY){
    foreach($element in $parent.ChildNodes){
     if($element.NodeType -ne [Xml.XmlNodeType]::Element){continue}
     if($element.HasAttribute('VisParentMinWidth') -and $parentWidth -le [int]$element.VisParentMinWidth){continue}
     if($element.HasAttribute('VisParentMaxWidth') -and $parentWidth -ge [int]$element.VisParentMaxWidth){continue}
     $left=if($element.HasAttribute('Left')){[double]$element.Left}else{0}
     $top=if($element.HasAttribute('Top')){[double]$element.Top}else{0}
     $itemWidth=if($element.HasAttribute('Width')){[double]$element.Width}else{$parentWidth}
     $itemHeight=if($element.HasAttribute('Height')){[double]$element.Height}else{44}
     $x=if($element.HoriCenter -eq '1'){($parentWidth-$itemWidth)/2+$left}elseif($left -lt 0){$parentWidth+$left}else{$left}
     if($top -lt 0){throw 'Negative transport y would escape the reserved footer'}
     if($element.Name -eq 'Static'){
      if($x -lt 0 -or $x+$itemWidth -gt $parentWidth -or $top+$itemHeight -gt 44){throw "Speed group escapes row at width $width"}
      Read-Controls $element $itemWidth ($offsetX+$x) ($offsetY+$top)
     }elseif($element.Name -in 'Button','Slider'){
      $rectangles.Add([pscustomobject]@{X=$offsetX+$x;Y=$offsetY+$top;W=$itemWidth;H=$itemHeight;Command=[string]$element.CmdID})
     }
    }
   }
   Read-Controls $activeBranches[0] $width 0 0
   foreach($rect in $rectangles){
    if($rect.X -lt 0 -or $rect.X+$rect.W -gt $width -or $rect.Y -lt 0 -or $rect.Y+$rect.H -gt 44){throw "Control escapes transport row at width $width : $($rect.Command)"}
   }
   for($a=0;$a -lt $rectangles.Count;$a++){
    for($b=$a+1;$b -lt $rectangles.Count;$b++){
     $one=$rectangles[$a];$two=$rectangles[$b]
     $overlap=[Math]::Min($one.X+$one.W,$two.X+$two.W)-[Math]::Max($one.X,$two.X) -gt 0 -and [Math]::Min($one.Y+$one.H,$two.Y+$two.H)-[Math]::Max($one.Y,$two.Y) -gt 0
     $alternatives=($one.Command -eq $two.Command) -or (($one.Command -in 'CMD_MEDIA_PLAY','CMD_MEDIA_PAUSE') -and ($two.Command -in 'CMD_MEDIA_PLAY','CMD_MEDIA_PAUSE')) -or (($one.Command -in 'CMD_PLAYLIST_WINDOW_ON','CMD_PLAYLIST_WINDOW_OFF') -and ($two.Command -in 'CMD_PLAYLIST_WINDOW_ON','CMD_PLAYLIST_WINDOW_OFF'))
     if($overlap -and -not $alternatives){throw "Overlapping controls at width $width : $($one.Command), $($two.Command)"}
    }
   }
  }
 }
}
$logo=[IO.File]::ReadAllText((Join-Path $SourceRoot 'Logo.txt'))
if(-not $logo.Contains('Sailor优化版')){throw 'Brand label is missing'}
Write-Host 'Validated references, nesting, four responsive footers and 18 width cases per layout; all speed controls stay inside the reserved transport row.'
