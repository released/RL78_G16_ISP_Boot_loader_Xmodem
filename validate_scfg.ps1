param([Parameter(Mandatory=$true)][string]$Project,[switch]$CheckOnly,
      [string]$LinkedImagePath='')
$ErrorActionPreference='Stop'
$Project=(Resolve-Path -LiteralPath $Project).Path
$name=Split-Path -Leaf $Project
if($name -notmatch '^RL78_(F24|G16|G22)_(ISP_Boot_loader_(UART|I2C|Xmodem)(_app)?|(UART|Xmodem|I2C_Slave)_Transfer)$'){throw 'Expected a named SC-owned RL78 serial project.'}
$mcu=$Matches[1];$bus=if($Matches[3]){$Matches[3]}elseif($Matches[5] -eq 'I2C_Slave'){'I2C'}else{$Matches[5]}
$boot=$Project
function Require($Test,[string]$Message){if(!$Test){throw ('SC consistency: '+$Message)}}
function Macro([string]$Path,[string]$Key){
    $text=[IO.File]::ReadAllText($Path);$m=[regex]::Match($text,'(?m)^\s*#define\s+'+[regex]::Escape($Key)+'\s+\(?\s*(0[xX][0-9A-Fa-f]+|[0-9]+)[uUlL]*\s*\)?')
    Require $m.Success ('Missing numeric macro '+$Key)
    if($m.Groups[1].Value -match '^0x'){return [Convert]::ToInt64($m.Groups[1].Value.Substring(2),16)}
    return [long]$m.Groups[1].Value
}
function Choice($Owner,[string]$Id){$n=$Owner.SelectSingleNode('.//option[@id="'+$Id+'"]');Require ($null -ne $n) ('Missing SC option '+$Id);return [string]$n.selection}
function ItemValue($Owner,[string]$Id){
    $n=$Owner.SelectSingleNode('.//option[@id="'+$Id+'"]');Require ($null -ne $n) ('Missing SC value '+$Id)
    $i=$n.SelectSingleNode('item[@id="'+$n.selection+'"]');Require ($null -ne $i) ('Missing SC selection '+$Id)
    if($i.HasAttribute('input') -and $i.GetAttribute('input') -ne ''){return $i.GetAttribute('input')}
    return $i.GetAttribute('value')
}
function RegValue([string]$Path,[string]$Register){
    $t=[IO.File]::ReadAllText($Path);$m=[regex]::Match($t,'(?m)^\s*'+[regex]::Escape($Register)+'\s*=\s*(?:_([0-9A-Fa-f]{2,4})_|(0[xX][0-9A-Fa-f]+|[0-9]+)[uUlL]*\s*;)')
    Require $m.Success ('Missing generated register '+$Register+' in '+[IO.Path]::GetFileName($Path))
    if($m.Groups[1].Success){return [Convert]::ToInt64($m.Groups[1].Value,16)}
    if($m.Groups[2].Value -match '^0x'){return [Convert]::ToInt64($m.Groups[2].Value.Substring(2),16)}
    return [long]$m.Groups[2].Value
}
$scfg=Join-Path $Project ($name+'.scfg');Require (Test-Path -LiteralPath $scfg -PathType Leaf) 'Missing project SCFG.'
[xml]$sc=[IO.File]::ReadAllText($scfg)
[xml]$mtpj=[IO.File]::ReadAllText((Join-Path $Project ($name+'.mtpj')))
$part=switch($mcu){F24 {'R7F124FPJ5xFB'} G16 {'R5F121BCxFP'} G22 {'R7F102GGExFB'}}
Require ($sc.smc.general.platform.id -ceq $part) ('SC MCU must be '+$part)
Require ($mtpj.SelectSingleNode('//DeviceName').InnerText -ceq $part) 'CS+ MCU differs from SC.'
Require ($mtpj.SelectSingleNode('//SCFGFile').InnerText -ceq ($name+'.scfg')) 'Missing/mismatched CS+ SC association.'
Require ($mtpj.SelectNodes('//CodeGenerator').Count -eq 0) 'Stale embedded Code Generator is still active.'
Require ($mtpj.SelectSingleNode('//COptionD-0').InnerText -match '(?m)^ISP_SCFG_REQUIRED\s*$') 'Missing required SC compile guard.'
$expected=@('r_bsp','Config_TAU0_1','Config_UART0',$(if($bus -eq 'I2C'){'Config_IICA0'}else{'Config_UART1'}))
$sw=$sc.SelectSingleNode('//tool[@id="SWComponent"]')
$actual=@($sw.SelectNodes('configuration')|ForEach-Object {$_.name})
Require (@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count -eq 0) 'Peripheral set must match the selected independent serial interface.'
$cpu=switch($mcu){F24 {40000000L} G16 {16000000L} G22 {32000000L}}
$clock=$sc.SelectSingleNode('//tool[@id="Clock"]')
Require (([double](ItemValue $clock 'fclk'))*1000 -eq $cpu) 'CPU frequency differs from the board adapter.'
if($mcu -eq 'F24'){
    Require ((Choice $clock 'hssclockenable') -eq 'check' -and (ItemValue $clock 'hssfrequency') -eq '4' -and (Choice $clock 'enablepll') -eq 'check' -and (Choice $clock 'pllfrequency') -eq 'frq80') 'F24 requires X1=4MHz / PLL80 / CPU40.'
    Require ((Choice $clock 'fmainswitcher') -eq 'hssclock_fmainswitcher' -and (Choice $clock 'fmpswitcher') -eq 'pll_fmpswitcher' -and (Choice $clock 'fmpdivider') -eq 'comboBox1-2' -and (Choice $clock 'fclkswitcher') -eq 'fmpswitcher_fclkswitcher') 'F24 clock source/divider differs from the board adapter.'
}else{
    Require ((Choice $clock 'hsocofrequency') -eq $(if($mcu -eq 'G16'){'frq16'}else{'frq32'})) 'HOCO frequency differs from this MCU profile.'
    Require ((Choice $clock 'highSpeedOCOenable') -eq 'hococlock_fihp' -and (Choice $clock 'fclkswitcher') -eq 'fmainswitcher_fclkswitcher') 'CPU must use the selected main HOCO clock.'
    Require ((Choice $clock 'fmainswitcher') -eq $(if($mcu -eq 'G16'){'grphococlock_fmainswitcher'}else{'focoswitcher_fmainswitcher'})) 'Main clock selector differs from the board adapter.'
    if($mcu -eq 'G22'){Require ((Choice $clock 'focoswitcher') -eq 'hococlock_focoswitcher') 'G22 must select HOCO, not MOCO.'}
}
$pinMap=switch($mcu){
    F24 {@{TXD0='54';RXD0='52';TXD1='42';RXD1='41';SCLA0='26';SDAA0='27'}}
    G16 {@{TxD0='22';RxD0='23';TxD1='12';RxD1='11';SCLA0='9';SDAA0='10'}}
    G22 {@{TxD0='20';RxD0='21';TxD1='35';RxD1='34';SCLA0='1';SDAA0='2'}}
}
foreach($key in $pinMap.Keys){
    if(($bus -eq 'I2C' -and $key -match '[TR][Xx][Dd]1') -or ($bus -ne 'I2C' -and $key -match 'S[CD][LA]A0')){continue}
    $pin=$sc.SelectSingleNode('//tool[@id="Pins"]/pinItem[@id="'+$key+'"]')
    Require ($null -ne $pin -and $pin.allocation -eq $pinMap[$key]) ('Pin route '+$key+' differs from the board adapter.')
}
foreach($c in $sw.SelectNodes('configuration')){foreach($s in $c.SelectNodes('.//isocket[@id="CountingClock"]')){Require ([double]::Parse($s.value,[Globalization.CultureInfo]::InvariantCulture) -eq $cpu) ('Stale SC clock socket in '+$c.name)}}
foreach($c in $sw.SelectNodes('configuration[starts-with(@name,"Config_UART")]')){
    foreach($key in @('dataLength','directionSetting','paritySetting','stopBitSetting','dataLevelSetting')){
        $required=switch($key){dataLength {'8bits'} directionSetting {'lsb'} paritySetting {'none'} stopBitSetting {'1bit'} dataLevelSetting {'normal'}}
        foreach($node in $c.SelectNodes('.//option[@id="'+$key+'"]')){Require ($node.selection -eq $required) ($c.name+' must use normal-polarity 8-N-1, LSB first.')}
    }
}
$gen=Join-Path $Project 'src\smc_gen'
$config=Join-Path $gen 'r_config\r_bsp_config.h'
Require (Test-Path -LiteralPath $config -PathType Leaf) 'Generate Code in Smart Configurator before Rebuild.'
if($mcu -eq 'G16'){
    # CC-RL takes option bytes from the project, not the IAR-only BSP macros.
    $optionBytes=@(0..3|ForEach-Object {Macro $config ('BSP_CFG_OPTBYTE'+$_+'_VALUE')})
    $userNode=$mtpj.SelectSingleNode('//LinkOptionUserOptByteValue-0')
    Require ($null -ne $userNode -and $userNode.InnerText -cmatch '^[0-9A-Fa-f]{6}$') 'G16 CC-RL user option bytes must contain exactly three bytes.'
    # The SC IAR-only no-WDT default is EF. CC-RL owns the legal C0 override;
    # leave generated files untouched so Generate Code cannot undo this policy.
    $optionBytes[0]=[Convert]::ToInt32($userNode.InnerText.Substring(0,2),16)
    Require (($optionBytes[0] -band 0xE0) -eq 0xE0) 'G16 C0 reserved bits7..5 must be111.'
    Require (!(($optionBytes[0] -band 0x10) -eq 0 -and ($optionBytes[0] -band 1) -ne 0)) 'G16 C0 prohibits WDTON=0 with WDSTBYON=1.'
    Require ($optionBytes[0] -eq 0xEE) 'G16 no-WDT profile requires C0=EE.'
    Require ($optionBytes[2] -eq 0xF9) 'G16 16MHz requires option byte C2=F9.'
    Require ($optionBytes[3] -eq 0x85) 'G16 debug profile requires option byte C3=85.'
    $userOptions=($optionBytes[0..2]|ForEach-Object {'{0:X2}' -f $_}) -join ''
    Require ($mtpj.SelectNodes('//LinkOptionUserOptByteValue-0').Count -eq 1 -and
        $mtpj.SelectSingleNode('//LinkOptionUserOptByte-0').InnerText -ceq 'True' -and
        $mtpj.SelectSingleNode('//LinkOptionUserOptByteValue-0').InnerText -ieq $userOptions) 'G16 CC-RL user option bytes differ from the generated SC profile.'
    Require ($mtpj.SelectNodes('//LinkOptionOcdbgValue-0').Count -eq 1 -and
        $mtpj.SelectSingleNode('//LinkOptionOcdbg-0').InnerText -ceq 'True' -and
        $mtpj.SelectSingleNode('//LinkOptionOcdbgValue-0').InnerText -ieq '85') 'G16 CC-RL OCD must be enabled with value85.'
    Require ($mtpj.SelectSingleNode('//LinkOptionSecurityOptByte-0').InnerText -ceq 'False' -and
        [string]::IsNullOrWhiteSpace($mtpj.SelectSingleNode('//LinkOptionSecurityOptByteValue-0').InnerText)) 'G16 security option byte must be disabled and empty; preserve the separate security ID.'
    $securityNode=$mtpj.SelectSingleNode('//LinkOptionSecurityId-0')
    Require ($mtpj.SelectNodes('//LinkOptionSecurityId-0').Count -eq 1 -and
        $null -ne $securityNode -and $securityNode.InnerText -cmatch '^[0-9A-Fa-f]{20}$') 'G16 security ID must explicitly contain ten bytes; an empty linker field leaves an unsafe HEX gap.'
    $securityId=$securityNode.InnerText.ToUpperInvariant()
    Require ($securityId -cne 'FFFFFFFFFFFFFFFFFFFF') 'G16 security ID must not be all FF.'
    $debugOwners=$mtpj.SelectNodes('//*[DebuggerProperty-EssentialProperty-Flash-IdCode-Length]')
    Require ($debugOwners.Count -gt 0) 'Missing G16 debugger security ID settings.'
    foreach($owner in $debugOwners){
        Require ($owner.SelectSingleNode('DebuggerProperty-EssentialProperty-Flash-IdCode-Length').InnerText -eq '10') 'G16 debugger security ID must contain ten bytes.'
        $debugId=''
        foreach($offset in 0..9){
            $node=$owner.SelectSingleNode('DebuggerProperty-EssentialProperty-Flash-IdCode-Code'+$offset)
            Require ($null -ne $node -and $node.InnerText -cmatch '^\d{1,3}$' -and [int]$node.InnerText -le 255) 'Malformed G16 debugger security ID byte.'
            $debugId+=('{0:X2}' -f [int]$node.InnerText)
        }
        Require ($debugId -ceq $securityId) 'G16 linker and debugger security ID values must match.'
    }
    if($LinkedImagePath){
        $image=[IO.Path]::GetFullPath($LinkedImagePath)
        Require ($image.StartsWith($Project+'\',[StringComparison]::OrdinalIgnoreCase)) 'Linked image must belong to the selected project.'
        Require (Test-Path -LiteralPath $image -PathType Leaf) 'Missing linked image.'
        $found=@{};$upper=0L;$eof=$false
        $reader=[IO.File]::OpenText($image)
        try{
        while($null -ne ($line=$reader.ReadLine())){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            Require (!$eof -and $line -cmatch '^:(?:[0-9A-Fa-f]{2})+$') 'Malformed Intel HEX record or data after EOF.'
            $record=@(for($i=1;$i -lt $line.Length;$i+=2){[Convert]::ToInt32($line.Substring($i,2),16)})
            Require ($record.Count -ge 5 -and $record.Count -eq $record[0]+5) 'Intel HEX record length mismatch.'
            Require ((($record|Measure-Object -Sum).Sum -band 255) -eq 0) 'Intel HEX checksum mismatch.'
            $count=$record[0];$address=$record[1]*256+$record[2];$type=$record[3]
            switch($type){
                0 {
                    $start=$upper+$address
                    Require ($start+$count -le 4294967296L) 'Intel HEX address overflow.'
                    for($i=0;$i -lt $count;$i++){
                        $at=$start+$i
                        if($at -ge 0xC0 -and $at -le 0xCD){
                            $key=[int]$at
                            Require (!$found.ContainsKey($key)) 'Overlapping linked option-byte records.'
                            $found[$key]=$record[4+$i]
                        }
                    }
                }
                1 {
                    Require ($count -eq 0 -and $address -eq 0) 'Malformed Intel HEX EOF.'
                    $eof=$true
                }
                2 {
                    Require ($count -eq 2 -and $address -eq 0) 'Malformed Intel HEX segment address.'
                    $upper=($record[4]*256L+$record[5])*16L
                }
                4 {
                    Require ($count -eq 2 -and $address -eq 0) 'Malformed Intel HEX linear address.'
                    $upper=($record[4]*256L+$record[5])*65536L
                }
                {$_ -in 3,5} {
                    Require ($count -eq 4 -and $address -eq 0) 'Malformed Intel HEX start address.'
                }
                default {throw 'SC consistency: Unsupported Intel HEX record type.'}
            }
        }
        }finally{$reader.Dispose()}
        Require $eof 'Missing Intel HEX EOF.'
        foreach($offset in 0..3){
            Require ($found.ContainsKey([int](0xC0+$offset)) -and
                $found[[int](0xC0+$offset)] -eq $optionBytes[$offset]) ('Linked G16 option byte mismatch/missing at '+('{0:X2}' -f (0xC0+$offset)))
        }
        foreach($offset in 0..9){
            Require ($found.ContainsKey([int](0xC4+$offset)) -and
                $found[[int](0xC4+$offset)] -eq [Convert]::ToInt32($securityId.Substring($offset*2,2),16)) ('Linked G16 security ID mismatch/missing at '+('{0:X2}' -f (0xC4+$offset)))
        }
        Write-Host 'PASS linked G16 C0..C3 match the CC-RL profile; SC-derived C1..C3; C0=EE/C2=F9/C3=85.'
        Write-Host 'PASS linked G16 C4..CD security ID matches the explicit linker and debugger settings.'
    }
}elseif($LinkedImagePath){
    throw 'Linked option-byte verification currently supports G16 only.'
}
$hoco=Macro $config 'BSP_CFG_HOCO_DIVIDE'
if($mcu -ne 'F24'){Require ($hoco -eq $(if($mcu -eq 'G16'){1}else{0})) 'Regenerate SC: stale HOCO register.'}
else{Require ((Macro $config 'BSP_CFG_FMP_DIVIDE') -eq 1 -and (Macro $config 'BSP_CFG_PLL_MULTI') -eq 3 -and (Macro $config 'BSP_CFG_HISYSCLK_SOURCE') -eq 1) 'Regenerate SC: stale F24 clock registers.'}
$timer=$sw.SelectSingleNode('configuration[@name="Config_TAU0_1"]')
Require ((ItemValue $timer 'IntervalValue16bits') -eq '1' -and (Choice $timer 'IntervalUnit16bits') -eq 'ms' -and (Choice $timer 'ClockSource') -eq 'FCLK1') 'The protocol tick requires a 1ms undivided TAU0_1.'
$reload=RegValue (Join-Path $gen 'Config_TAU0_1\Config_TAU0_1.c') 'TDR01'
Require ($reload -eq $cpu/1000-1) 'Regenerate SC: stale timer reload.'
$log=$sw.SelectSingleNode('configuration[@name="Config_UART0"]')
$logBaud=[long](ItemValue $log 'baudrateSetting')
Require ($logBaud -ge 300 -and $logBaud -le 2000000) 'UART0 baud must be 300..2000000.'
$logDiv=[long][Math]::Floor(($cpu/2+$logBaud)/(2*$logBaud))
$logSdr=RegValue (Join-Path $gen 'Config_UART0\Config_UART0.c') 'SDR00'
Require ($logDiv -ge 1 -and $logDiv -le 128 -and $logSdr -eq ($logDiv-1)*512) 'Regenerate SC: stale UART0 divisor.'
Require ([Math]::Abs($cpu/2/(2*$logDiv)-$logBaud)*100 -le $logBaud*2) 'UART0 divisor error exceeds two percent.'
foreach($node in $log.SelectNodes('.//option[@id="Prescaler"]')){Require ($node.selection -eq 'FCLK1') 'UART0 source must be fCLK/2.'}
$values=[ordered]@{CPU_HZ=$cpu;HOCO_DIVIDE=$hoco;LOG_SDR=$logSdr;TIMER_RELOAD=$reload}
$transport=Join-Path $boot 'isp_transport_config.h'
if($bus -eq 'I2C'){
    $i2c=$sw.SelectSingleNode('configuration[@name="Config_IICA0"]')
    $rate=Macro $transport 'ISP_BUS_RATE';$address=Macro $transport 'ISP_I2C_ADDRESS'
    Require ([long](ItemValue $i2c 'address') -eq ($address*2)) 'SC SVA address must equal the seven-bit contract address shifted left by one.'
    Require ((Choice $i2c 'operationMode') -eq $(if($rate -eq 100000){'standard'}elseif($rate -eq 400000){'fastmode'}else{'INVALID'})) 'IICA standard/fast mode differs from the metadata rate.'
    $file=Join-Path $gen 'Config_IICA0\Config_IICA0.c'
    Require ((RegValue $file 'SVA0') -eq ($address*2)) 'Regenerate SC: stale IICA address.'
    $values.IICA_WL=RegValue $file 'IICWL0';$values.IICA_WH=RegValue $file 'IICWH0'
    $values.IICA_PRS=if($mcu -eq 'G16'){0}else{RegValue $file 'PRS0'}
}else{
    $uart=$sw.SelectSingleNode('configuration[@name="Config_UART1"]');$baud=Macro $transport 'ISP_UART_BAUD'
    foreach($node in $uart.SelectNodes('.//option[@id="baudrateSetting"]')){Require ([long](ItemValue $node.ParentNode 'baudrateSetting') -eq $baud) 'UART1 baud differs from Boot/App metadata; edit the contract and SC together.'}
    foreach($node in $uart.SelectNodes('.//option[@id="Prescaler"]')){Require ($node.selection -eq 'FCLK1') 'UART1 source must be fCLK/2.'}
    $div=[long][Math]::Floor(($cpu/2+$baud)/(2*$baud));$reg=if($mcu -eq 'F24'){'SDR10'}else{'SDR02'}
    $sdr=RegValue (Join-Path $gen 'Config_UART1\Config_UART1.c') $reg
    Require ($div -ge 1 -and $div -le 128 -and $sdr -eq ($div-1)*512) 'Regenerate SC: stale UART1 divisor.'
}
$text="/* Generated from this project's validated SC output. Do not edit. */`n#ifndef ISP_SCFG_CONFIG_H`n#define ISP_SCFG_CONFIG_H`n"
foreach($key in $values.Keys){$text+=('#define ISP_SCFG_{0} ({1}UL)' -f $key,$values[$key])+"`n"}
$text+="#endif`n";$header=Join-Path $Project 'sc_peripheral_config.generated.h'
if(!(Test-Path -LiteralPath $header) -or [IO.File]::ReadAllText($header).Replace("`r`n","`n") -cne $text){
    if($CheckOnly){throw 'Stale SC peripheral projection. Run normal project Rebuild.'}
    [IO.File]::WriteAllText($header,$text,(New-Object Text.UTF8Encoding($false)))
}
Write-Host ('PASS SC MCU/pins/clocks/serial/timer and actual generated registers: '+$name)
