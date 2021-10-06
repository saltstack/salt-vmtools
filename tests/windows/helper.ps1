function Write-TestLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Label,

        [Parameter(Mandatory=$false)]
        [String] $Filler = "-"
    )
    $total = 80 - $Label.Length
    $begin = [math]::Floor($total / 2)
    $leftover = $total % 2
    $end = $begin + $leftover
    Write-Host "$("$Filler" * $begin) $Label $("$Filler" * $end)"
}


function Write-Label {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Label
    )
    Write-TestLabel $Label -Filler "="
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
