# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

$psobj = [PSCustomObject]@{
    spongebob = "sqarepants"
    patrick = "star"
    friends = [PSCustomObject]@{
        squidward = "tentacles"
        sandy = "cheeks"
    }
}

function test_Convert-PSObjectToHashTable {
    $failed = 0
    if ( $psobj -isnot [PSCustomObject]) { $failed = 1 }
    $hash = Convert-PSObjectToHashTable -InputObject $psobj
    if ( $hash -isnot [Hashtable]) { $failed = 1 }
    return $failed
}
