
<#
.DESCRIPTION
Return NDCs for either a ATC class or drug name. 
.PARAMETER ATCClass
The ATC (Anatomical Therapeutic Category) therapeutic class for which NDCs will be returned.  These classes
can be identified on the NIH website.  Classes with spaces need to 
be wrapped in double-quotes. 
.PARAMETER DrugName
Generic drug name for which NDCs will be returned. Names containing spaces must be wrapped in double-quotes  
.PARAMETER CSVOut
Path and filename for CSV output file.  If no fully-qualified path is listed, the file is saved in the 
current working directory.  Filenames that exist in the path are automatically overwritten. 
.EXAMPLE
PS> .\FetchNDCs.ps1 -ATCClass "beta blocking agents" -CSVOut .\betablockerNDCs.csv
.EXAMPLE
PS> .\FetchNDCs.ps1 -DrugName metoprolol -CSVOut .\metoprololNDCs.csv
.SYNOPSIS
The following script retrieves NDC information for a given ATC therapeutic class or drug name. Optionally, 
the information can be saved to a CSV file provided in the command line parameters.

NOTE: You will need to execute this script as an administrator or have administrative privileges.
Prior to running script, execute "Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force" from the PS command line
.LINK 
https://mor.nlm.nih.gov/RxClass/
#>

[CmdletBinding()]
param (
   [Parameter(ParameterSetName='class')] [string] $ATCClass,
   [Parameter(ParameterSetName='drug')] [string] $DrugName,
   [string] $CSVOut
)

$RESTAPI_rxgetClass="https://rxnav.nlm.nih.gov/REST/rxclass/class/byName.json?className=@1&classTypes=ATC1-4"
$RESTAPI_rxgetClassMembers="https://rxnav.nlm.nih.gov/REST/rxclass/classMembers.json?classId=@1&relaSource=ATC"
$RESTAPI_rxgetNDCs="https://rxnav.nlm.nih.gov/REST/ndcproperties.json?id=@1"
$RESTAPI_rxgetRelated = "https://rxnav.nlm.nih.gov/REST/rxcui/@1/related.json?tty=SCD+SBD+GPCK+BPCK"


#additional drug-specific data APIs to provider further detail: e.g., brand name, label information, etc. 
$RESTAPI_rxgetDrugs="https://rxnav.nlm.nih.gov/REST/rxcui.json?name=@1&search=2"
$RESTAPI_rxTermInfo="https://rxnav.nlm.nih.gov/REST/RxTerms/rxcui/@1/allinfo.json"
$RESTAPI_rxNDCProps = "https://rxnav.nlm.nih.gov/REST/ndcproperties.json?id=@1"
$RESTAPI_FDAgetDrugProps = "https://api.fda.gov/drug/ndc.json?search=generic_name:@1&limit=1000"
$RESTAPI_FDAgetDrugClassProps = "https://api.fda.gov/drug/ndc.json?search=pharm_class:@1&limit=1000"

function fetchNDCsbyDrugName {
    [CmdletBinding()]
    param (
       [Parameter(Mandatory)]
       [string] $DrugName
    )
    $rxcuis=@()
    $ndcinfo=@()
    Write-Host "`r`nRetrieving therapeutic class information for $($DrugName)..."
    $uri = $RESTAPI_rxgetDrugs -replace '@1',($DrugName -replace ' ','%20')
    Write-Host "`r`nInvoking RxNav REST API web request: $($uri)`r`n"
    $ProgressPreference = 'SilentlyContinue'
    $RxNormID = ConvertFrom-Json (Invoke-WebRequest $uri)
    $ProgressPreference = 'Continue'
    if ($RxNormID -and $RxNormID.PSobject.Properties.name `
        -contains "idGroup") {
       foreach ($rxcui in $RxNormID.idGroup.rxnormId) {
            $ProgressPreference = 'SilentlyContinue'
            $related = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxgetRelated `
            -replace '@1', $rxcui))
            $ProgressPreference = 'Continue'
            if ($related -and $related.relatedGroup.conceptGroup.Length -gt 0) {
                foreach($term in $related.relatedGroup.conceptGroup) {
                   if ($term.PSobject.Properties.name -contains "conceptProperties") {
                      foreach($concept in $term.conceptProperties) {
                         if (@($rxcuis | ? { $_.RxCUI -eq $concept.rxcui }).Count -eq 0) {
                              $rxcuis += [PSCustomObject] @{
                                         'RxCUI'=$concept.rxcui;
                                         'Name'=$concept.name;
                                         'TermType'=$term.tty; 
                                         'Synonym'=$concept.synonym}
                         }
                       }
                                         
                   }
               }
               if (@($rxcuis).Count -gt 0) {
                    Write-Host "We are here"
                    $total = @($rxcuis).Count
                    $i = 0
                    foreach ($concept in @($rxcuis)) {
                       $ProgressPreference = 'SilentlyContinue'
                       $ndcprops = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxNDCProps -replace '@1', $concept.rxcui)) 
                       $ndcmisc = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxTermInfo -replace '@1', $concept.rxcui))   
                       $ProgressPreference = 'Continue'             
                       if ($ndcprops.PSobject.Properties.name -contains "ndcPropertyList" `
                          -and $ndcmisc.PSobject.Properties.name -contains "rxtermsProperties") {
                          foreach($prop in $ndcprops.ndcPropertyList.ndcProperty) {
                             $ndcinfo += [PSCustomObject] @{
                                         'RxCUI' = $concept.rxcui;
                                         'TermType' = $ndcmisc.rxtermsProperties.termType;
                                         'Name' = $ndcmisc.rxtermsProperties.fullGenericName;
                                         'NDC' = $prop.ndcItem;
                                         'NDC9' = $prop.ndc9;
                                         'NDC10' = $prop.ndc10;
                                         'SPLID' = $prop.splSetIdItem;
                                         'Desc' = if ($prop.PSObject.Properties.name -contains 'packagingList') `
                                          { $prop.packagingList.packaging[0] } else { "--" };
                                         'Mfg' = ($prop.propertyConceptList.propertyConcept | ? `
                                          { $_.propName -eq "LABELER" }).propValue;
                                         'Route' = $ndcmisc.rxtermsProperties.route;
                                         'Strength' = $ndcmisc.rxtermsProperties.strength;}
                           }
                       }
                       $i += 1
                       $PercentComplete = [int](($i/$total) * 100)
                       Write-Progress -Activity "Retrieving NDCs for concepts" `
                       -Status "$PercentComplete% Complete:" -PercentComplete $PercentComplete
                    }   
               }
               else {
                    Write-Host "No NDCs located via RxNav. Trying openFDA API..."
                    try {
                        $ProgressPreference = 'SilentlyContinue'
                        $fda_drug = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_FDAgetDrugProps -replace '@1', `
                        ($DrugName -replace ' ','+AND+'))) 
                        $ProgressPreference = 'Continue'
                        if ($fda_drug -and @($fda_drug.results).Count -gt 0) {
                            foreach ($item in @($fda_drug.results)) {
                                foreach ($pkg in @($item.packaging))  {
                                    $NDCparts = $pkg.package_ndc.Split('-')  
                                    $NDC11 = ''
                                    if (@($NDCparts).Count -gt 0) {
                                        $ndc1 = if ($NDCparts[0].Length -eq 4) { ("0" + $NDCparts[0]) } else { $NDCparts[0] }
                                        $ndc2 = if ($NDCparts[1].Length -eq 3) { ("0" + $NDCparts[1]) } else { $NDCparts[1] }
                                        $ndc3 = if ($NDCparts[2].Length -eq 1) { ("0" + $NDCparts[2]) } else { $NDCparts[2] }
                                        $NDC11 = $ndc1 + $ndc2 + $ndc3
                                    }
                                    else {
                                        $NDC11 = $pkg.package_ndc.Remove('-')
                                    }
                         
                                    $ndcinfo += [PSCustomObject] @{
                                            'RxCUI' = '--';
                                            'TermType' = '--';
                                            'Name' = $item.generic_name + " (" + $item.brand_name + ")";
                                            'NDC' = $NDC11;
                                            'NDC9' = $item.product_ndc;
                                            'NDC10' = $pkg.package_ndc;
                                            'SPLID' = $item.spl_id;
                                            'Desc' = $pkg.description;
                                            'Mfg' = $item.labeler_name;
                                            'Route' = $item.route[0].ToLower(); 
                                            'Strength' = $item.active_ingredients[0].strength;}
                                }
                            }
                        }
                    }
                    catch {
                        # do nothing for now.  Prevents exception error from popping up for no results being returned by API
                    }
               
               } 
             }    
       }
    }
    return @($ndcinfo);
}

function fetchNDCsbyATC {
    [CmdletBinding()]
    param (
       [Parameter(Mandatory)]
       [string] $ATCClass
    )

    $rxcuis=@()
    $ndcinfo=@()
    $found_concepts = $false
    Write-Host "`r`nRetrieving therapeutic class information for $($ATCClass)..."
    $uri = $RESTAPI_rxgetClass -replace '@1',($ATCClass -replace ' ','%20') 
    Write-Host "`r`nInvoking RxNav REST API web request: $($uri)`r`n"
        $ProgressPreference = 'SilentlyContinue'
        $rootclass = ConvertFrom-Json (Invoke-WebRequest $uri)
        $ProgressPreference = 'Continue'
        if ($rootclass -and $rootclass.rxclassMinConceptList.rxclassMinConcept.Length -gt 0) {
            Write-Host "Retrieving drug concepts...`r`n"     
            foreach($class in $rootclass.rxclassMinConceptList.rxclassMinConcept) {
                $ProgressPreference = 'SilentlyContinue'
                $classmembers = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxgetClassMembers `
                -replace '@1', $class.classId))        
                $ProgressPreference = 'Continue'
                foreach($c in $classmembers.drugMemberGroup.drugMember) {
                   if (@($rxcuis | ? { $_.RxCUI -eq $c.minConcept.rxcui }).Count -eq 0) {
                       $rxcuis += [PSCustomObject] @{
                                  'RxCUI'=$c.minConcept.rxcui;
                                  'Name'=$c.minConcept.name;
                                  'TermType'=$c.minConcept.tty; 
                                  'Synonym'='--'}
                       #get RxCUIs for all related generic and brand concept
                       $ProgressPreference = 'SilentlyContinue'
                       $related = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxgetRelated `
                       -replace '@1', $c.minConcept.rxcui))
                       $ProgressPreference = 'Continue'
                       if ($related -and $related.relatedGroup.conceptGroup.Length -gt 0) {
                           foreach($term in $related.relatedGroup.conceptGroup) {
                               if ($term.PSobject.Properties.name -contains "conceptProperties") {
                                  $found_concepts = $true
                                  foreach($concept in $term.conceptProperties) {
                                     if (@($rxcuis | ? { $_.RxCUI -eq $concept.rxcui }).Count -eq 0) {
                                         $rxcuis += [PSCustomObject] @{
                                                    'RxCUI'=$concept.rxcui;
                                                    'Name'=$concept.name;
                                                    'TermType'=$term.tty; 
                                                    'Synonym'=$concept.synonym}
                                          }
                                     }
                                  }
                            }
                       } 
                   } 
                }
             }
        }
        if (@($rxcuis).Count -gt 0 -and $found_concepts) {
            $total = @($rxcuis | ? { @("IN","MIN") -notcontains $_.TermType } ).Count
            $i = 0
            foreach ($concept in @($rxcuis | ? { @("IN","MIN") -notcontains $_.TermType } )) {
                $ProgressPreference = 'SilentlyContinue'
                $ndcprops = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxNDCProps -replace '@1', $concept.rxcui)) 
                $ndcmisc = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxTermInfo -replace '@1', $concept.rxcui))   
                $ProgressPreference = 'Continue'             
                if ($ndcprops.PSobject.Properties.name -contains "ndcPropertyList" `
                -and $ndcmisc.PSobject.Properties.name -contains "rxtermsProperties") {
                    foreach($prop in $ndcprops.ndcPropertyList.ndcProperty) {
                        $ndcinfo += [PSCustomObject] @{
                                'RxCUI' = $concept.rxcui;
                                'TermType' = $ndcmisc.rxtermsProperties.termType;
                                'Name' = $ndcmisc.rxtermsProperties.fullGenericName;
                                'NDC' = $prop.ndcItem;
                                'NDC9' = $prop.ndc9;
                                'NDC10' = $prop.ndc10;
                                'SPLID' = $prop.splSetIdItem;
                                'Desc' = if ($prop.PSObject.Properties.name -contains 'packagingList') `
                                    { $prop.packagingList.packaging[0] } else { "--" };
                                'Mfg' = ($prop.propertyConceptList.propertyConcept | ? `
                                    { $_.propName -eq "LABELER" }).propValue;
                                'Route' = $ndcmisc.rxtermsProperties.route;
                                'Strength' = $ndcmisc.rxtermsProperties.strength;
                        }
                    }
                  }
                  $i += 1
                  $PercentComplete = [int](($i/$total) * 100)
                  Write-Progress -Activity "Retrieving NDCs for concepts" -Status "$PercentComplete% Complete:" -PercentComplete $PercentComplete
            }
                
        }
        else {
                if ($rootclass -and $rootclass.rxclassMinConceptList.rxclassMinConcept.Length -gt 0) {
                   Write-Host "No NDCs located via RxNav. Trying openFDA API..."
                   foreach($class in $rootclass.rxclassMinConceptList.rxclassMinConcept) {
                        $ProgressPreference = 'SilentlyContinue'
                        $classmembers = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_rxgetClassMembers `
                        -replace '@1', $class.classId))        
                        $ProgressPreference = 'Continue'
                        foreach($c in $classmembers.drugMemberGroup.drugMember) {   
                            try {
                                $ProgressPreference = 'SilentlyContinue'
                                $fda_drug = ConvertFrom-Json (Invoke-WebRequest ($RESTAPI_FDAgetDrugProps -replace '@1', `
                                ($c.minConcept.name -replace ' ','+AND+'))) 
                                $ProgressPreference = 'Continue'
                                if ($fda_drug -and @($fda_drug.results).Count -gt 0) {
                                    foreach ($item in @($fda_drug.results)) {
                                        foreach ($pkg in @($item.packaging)) {
                                             $NDCparts = $pkg.package_ndc.Split('-')  
                                             $NDC11 = ''
                                             if (@($NDCparts).Count -gt 0) {
                                                $ndc1 = if ($NDCparts[0].Length -eq 4) { ("0" + $NDCparts[0]) } else { $NDCparts[0] }
                                                $ndc2 = if ($NDCparts[1].Length -eq 3) { ("0" + $NDCparts[1]) } else { $NDCparts[1] }
                                                $ndc3 = if ($NDCparts[2].Length -eq 1) { ("0" + $NDCparts[2]) } else { $NDCparts[2] }
                                                $NDC11 = $ndc1 + $ndc2 + $ndc3
                                             }
                                             else {
                                                $NDC11 = $pkg.package_ndc.Remove('-')
                                             }
                         
                                             $ndcinfo += [PSCustomObject] @{
                                                'RxCUI' = '--';
                                                'TermType' = '--';
                                                'Name' = $item.generic_name + " (" + $item.brand_name + ")";
                                                'NDC' = $NDC11;
                                                'NDC9' = $item.product_ndc;
                                                'NDC10' = $pkg.package_ndc;
                                                'SPLID' = $item.spl_id;
                                                'Desc' = $pkg.description;
                                                'Mfg' = $item.labeler_name;
                                                'Route' = $item.route[0].ToLower(); 
                                                'Strength' = $item.active_ingredients[0].strength;
                                            }
                                        }
                                    }
                                }
                            }
                            catch {
                                # do nothing for now.  Prevents exception error from popping up for no results being returned by API
                            }
                        }
                        
                   }
                   
                }
        }
        return @($ndcinfo);
}


$ndcs = $null
$opt = $null
$selOpts = $PSCmdlet.ParameterSetName

if ($selOpts -eq 'class') { 
    $opt = $ATCClass
    $ndcs = fetchNDCsbyATC -ATCClass $ATCClass
} 
elseif ($selOpts -eq 'drug') { 
    $opt = $DrugName
    $ndcs = fetchNDCsbyDrugName -DrugName $DrugName 
} 

if (@($ndcs).Count -eq 0 -or $ndcs -eq $null) {
       Write-Host "No concepts were identified for $($opt).  Please verify the class or drug name, spelling, etc."
       exit
} 

if ($CSVOut -and @($ndcs).Count -gt 0) { 
    $filename = (Split-Path $CSVOut- -Leaf).TrimEnd('-')
    $parent = (Split-Path $CSVOut -Parent).ToString()
    $path = ''
    if ($Parent -eq $null -or $Parent.Length -eq 0) {
        $path = (Get-Location).Path
        $path = $path + "\$($filename)"
        $parent = (Split-Path $path -Parent).ToString()
    }
    else {
        $path=$CSVOut
    }
    if (Test-Path -Path $path) { Remove-Item -Path $path -Force }
    $NDCtotal = @($ndcs).Count
    Write-Host "Writing $($NDCtotal) NDC records to $($path)."
    $ndcs | Export-Csv -Path $path -NoTypeInformation
}
elseif (@($ndcs).Count -gt 0) {
   $NDCtotal = @($ndcs).Count
   $ndcs | Format-Table -Property Name, RxCUI, NDC, NDC9, NDC10, Desc, Mfg, Route, Strength -AutoSize
   Write-Host "Summary: $($NDCtotal) NDCs identified for $($opt)`r`n"
}


 

