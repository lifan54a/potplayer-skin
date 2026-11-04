$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$themes=@(
 @{Name='铂金灰';Accent='#BCC5CF';Background='#191B1F'},
 @{Name='香槟金';Accent='#C5B18A';Background='#1E1C19'},
 @{Name='烟铜';Accent='#BB9B8D';Background='#211C1A'},
 @{Name='钛蓝';Accent='#93A8B8';Background='#191E23'}
)
$form=[Windows.Forms.Form]::new()
$form.Text='Sailor优化版 · 主题配色';$form.Size=[Drawing.Size]::new(480,370)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
$themeSelect=[Windows.Forms.ComboBox]::new();$themeSelect.Location=[Drawing.Point]::new(24,24)
$themeSelect.Size=[Drawing.Size]::new(410,28);$themeSelect.DropDownStyle='DropDownList'
$themes|ForEach-Object{[void]$themeSelect.Items.Add($_.Name)}
$preview=[Windows.Forms.Panel]::new();$preview.Location=[Drawing.Point]::new(24,70);$preview.Size=[Drawing.Size]::new(410,100)
$brand=[Windows.Forms.Label]::new();$brand.Text='Sailor优化版';$brand.Location=[Drawing.Point]::new(18,18);$brand.AutoSize=$true
$speed=[Windows.Forms.Label]::new();$speed.Text='00:14:10       −    1.0×    +';$speed.Location=[Drawing.Point]::new(18,56);$speed.AutoSize=$true
$preview.Controls.AddRange(@($brand,$speed))
$accentButton=[Windows.Forms.Button]::new();$accentButton.Text='自定义强调色';$accentButton.Location=[Drawing.Point]::new(24,188);$accentButton.Size=[Drawing.Size]::new(196,36)
$backgroundButton=[Windows.Forms.Button]::new();$backgroundButton.Text='自定义背景色';$backgroundButton.Location=[Drawing.Point]::new(238,188);$backgroundButton.Size=[Drawing.Size]::new(196,36)
$summary=[Windows.Forms.Label]::new();$summary.Location=[Drawing.Point]::new(24,236);$summary.Size=[Drawing.Size]::new(410,24)
$export=[Windows.Forms.Button]::new();$export.Text='生成皮肤文件…';$export.Location=[Drawing.Point]::new(24,274);$export.Size=[Drawing.Size]::new(410,38)
$script:accent='#BCC5CF';$script:background='#191B1F'
function Update-Preview {
 $preview.BackColor=[Drawing.ColorTranslator]::FromHtml($script:background)
 $brand.ForeColor=[Drawing.Color]::FromArgb(180,180,180)
 $speed.ForeColor=[Drawing.ColorTranslator]::FromHtml($script:accent)
 $summary.Text="强调色 $script:accent    背景色 $script:background"
}
$themeSelect.Add_SelectedIndexChanged({
 $selected=$themes[$themeSelect.SelectedIndex]
 $script:accent=$selected.Accent;$script:background=$selected.Background;Update-Preview
})
$accentButton.Add_Click({
 $dialog=[Windows.Forms.ColorDialog]::new();$dialog.FullOpen=$true;$dialog.Color=[Drawing.ColorTranslator]::FromHtml($script:accent)
 if($dialog.ShowDialog() -eq 'OK'){$script:accent='#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R,$dialog.Color.G,$dialog.Color.B;Update-Preview}
 $dialog.Dispose()
})
$backgroundButton.Add_Click({
 $dialog=[Windows.Forms.ColorDialog]::new();$dialog.FullOpen=$true;$dialog.Color=[Drawing.ColorTranslator]::FromHtml($script:background)
 if($dialog.ShowDialog() -eq 'OK'){$script:background='#{0:X2}{1:X2}{2:X2}' -f $dialog.Color.R,$dialog.Color.G,$dialog.Color.B;Update-Preview}
 $dialog.Dispose()
})
$export.Add_Click({
 $save=[Windows.Forms.SaveFileDialog]::new();$save.Filter='PotPlayer 皮肤 (*.dsf)|*.dsf';$save.FileName='Sailor优化版_自定义.dsf'
 if($save.ShowDialog() -eq 'OK'){
  try{
   $export.Enabled=$false;$form.UseWaitCursor=$true
   & (Join-Path $PSScriptRoot 'Build-Skin.ps1') -AccentColor $script:accent -BackgroundColor $script:background -ThemeName '自定义' -OutputFile $save.FileName | Out-Null
   [void][Windows.Forms.MessageBox]::Show("已生成：`r`n$($save.FileName)",'导出成功')
  }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'生成失败')}
  finally{$export.Enabled=$true;$form.UseWaitCursor=$false}
 }
 $save.Dispose()
})
$form.Controls.AddRange(@($themeSelect,$preview,$accentButton,$backgroundButton,$summary,$export))
$themeSelect.SelectedIndex=0
[void]$form.ShowDialog();$form.Dispose()
