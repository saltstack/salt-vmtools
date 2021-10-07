function Write-Header {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Label,

        [Parameter(Mandatory=$false)]
        [String] $Filler = "="
    )
    if($Label) {
        $total = 80 - $Label.Length
        $begin = [math]::Floor($total / 2)
        $leftover = $total % 2
        $end = $begin + $leftover
        Write-Host "$("$Filler" * $begin) $Label $("$Filler" * $end)"
    } else {
        Write-Host "$("$Filler" * 82)"
    }
}


function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Failed
    )
    if ($Failed -ne 0) {
        $msg = "Failed"
        $color = "Red"
    } else {
        $msg = "Success"
        $color = "Green"
    }
    $total = 80 - $msg.Length
    $begin = [math]::Floor($total / 2)
    $leftover = $total % 2
    $end = $begin + $leftover
    Write-Host "$(":" * $begin) " -NoNewline
    Write-Host $msg -NoNewline -ForegroundColor $color
    Write-Host " $(":" * $end)"
}
