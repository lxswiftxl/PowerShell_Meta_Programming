#Global Vars
$SectionPatterns = "^::.*|^##.*" #This pattern matches on section header starts
$SectionPatternCharactersToReplace = "[:|#]" #This pattern matches on characters to replace when sanatizing the section header
[System.Collections.ArrayList]$SectionHeaderVariables = @()
[System.Collections.ArrayList]$ParametersInformation = @()
#Line matching
$LinePatterns = "^/.*"
$VerbosePreference = 'Continue' #Debugging my code

#Location of the binary file we want to scan
Set-Location 'C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy'

#Binary we want to convert, you know I'm really developing a hatred for legacy console applications
$BinaryHelpInfo = .\AzCopy.exe /?

#Basic sanitization of the help data, removes excess lines and leading/trailing spaces
$BinaryHelpInfo = $BinaryHelpInfo | Where-Object {$_}

#Loop through the file and find the major sections of data
for ($i = 0; $i -lt $BinaryHelpInfo.Count; $i++) {
    $BinaryHelpInfoHeaderMatch = $BinaryHelpInfo[$i] -match $SectionPatterns

    if ($BinaryHelpInfoHeaderMatch) {
        Write-Verbose "We matched a section header on line ""$($BinaryHelpInfo[$i])""" #Quotes for character escaping

        #Set a temp variable as a indicator that we hit a section header
        $SectionHeaderLine = $true

        #Attempt to strip out the header name so we can use it later
        $HeaderNameReplaced = ($BinaryHelpInfo[$i] -replace $SectionPatternCharactersToReplace, '').Trim()
        if ($HeaderNameReplaced) {
            Write-Verbose "Section Header Name is $HeaderNameReplaced"
            $Script:SectionHeaderName = $HeaderNameReplaced
        }
    } elseif (
            ($SectionHeaderLine) -and
            (!($BinaryHelpInfoHeaderMatch))
        ) {
        if ($SectionHeaderLine) {
            Write-Verbose "Line $i is the first line after the Section Header, were going to make a new storage var and flip a switch"
            $SectionVariableCountInt = 1
            do {
                $SectionVariableName = "Section$($SectionVariableCountInt)"
                if (!(Get-Variable $SectionVariableName -ErrorAction SilentlyContinue)) {
                    Write-Verbose "$SectionVariableCountInt is free, using that value for SectionVariableName"
                    New-Variable $SectionVariableName
                    $SectionVariableCreated = $true
                    Try {
                        $SectionHeaderNameObject = New-Object -TypeName psobject
                        $SectionHeaderNameObject | Add-Member -MemberType NoteProperty -Name 'SectionVariable' -Value $SectionVariableName
                        $SectionHeaderNameObject | Add-Member -MemberType NoteProperty -Name 'HeaderName' -Value $Script:SectionHeaderName

                        $SectionHeaderVariables.Add($SectionHeaderNameObject) | Out-Null
                    } Catch {}
                    $i = $i - 1 #Step the loop back int 1 so we don't miss the line
                } else {
                    $SectionVariableCreated = $false
                    Write-Verbose "$SectionVariableName was taken, incrementing +1 and looping"
                    $SectionVariableCountInt++
                }
            } until ($SectionVariableCreated)

            #Let PowerShell know to start storing data to the new variable
            $SectionHeaderLine = $false
        }
        Write-Verbose "Line $i is after the section header ending, we will start processing it"
    } elseif (
            (!($SectionHeaderLine)) -and
            (!($BinaryHelpInfoHeaderMatch)) -and
            ($SectionHeaderVariables) #So we don't run this block on the first few lines
        ) {

        #Populate the Section variable with content
        Set-Variable -Name $SectionVariableName -Value @(
            (Get-Variable -Name $SectionVariableName).Value #Add the existing value so we don't lose it
            $BinaryHelpInfo[$i] #Add new line info
        )
    } #end Normal Line elseif
} #End for loop

#Find all sections that have actual options available
$SectionHeaderVariablesWithOptions = $SectionHeaderVariables | Where-Object {($PSItem.HeaderName -like "*Options*")}

foreach ($Section in $SectionHeaderVariablesWithOptions) {
    $Lines = (Get-Variable -Name $Section.SectionVariable).Value | Where-Object {$PSItem} #Get the value and remove blank lines

    for ($i = 0; $i -lt $array.Count; $i++) {
        if ($Lines[$i] -match $LinePatterns) {
            if ($ParameterName -and $ParameterHelpInfo) {
                Write-Verbose 'We found an existing parameter so we will add it to the ArrayList'
                
                $ParameterToAdd = New-Object -TypeName psobject
                $ParameterToAdd | Add-Member -MemberType NoteProperty -Name 'ParameterName' -Value $ParameterName
                $ParameterToAdd | Add-Member -MemberType NoteProperty -Name 'ParameterHelp' -Value $ParameterHelpInfo

                $ParametersInformation.Add($ParameterToAdd) | Out-Null
                #Remove the previous parameter information
                Remove-Variable ParameterName,ParameterHelpInfo,ParameterHelpString
            }

           $LineSplit = ($Lines[$i].Split(':') -replace '/','').Trim()
           
           if ($LineSplit.Count -gt 1) { 
                $ParameterName = $LineSplit[0]
                $ParameterHelpString = (($Lines[$i].Split(':') -replace '/','').Trim()[-1] -replace '<*.*>','').Trim()

                #Establish a variable to hold the help information in
                [System.Collections.ArrayList]$ParameterHelpInfo = @()

                #Add the help information to the HelpInfo Property
                $ParameterHelpInfo.Add($ParameterHelpString) | Out-Null
            } elseif ($Lines[$i].Trim() -notmatch $LinePatterns) {
               $ParameterHelpInfo.Add($Lines[$i].Trim())
           }
        }
    }
}