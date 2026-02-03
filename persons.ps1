##################################################
# HelloID-Conn-Prov-Source-C-Quential-Persons
#
# Version: 1.0.0
##################################################
# Initialize default value's
$config = $configuration | ConvertFrom-Json

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Invoke-C-QuentialRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [Parameter()]
        [object]
        $Headers
    )

    process {
        try {
            $apiUrl = "$($config.BaseUrl)/laravel/api/v3/$Uri"

            $splatParams = @{
                Uri         = $apiUrl
                Method      = 'GET'
                ContentType = 'application/json'
                Headers     = $headers
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Resolve-C-QuentialError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($httpErrorObj.ErrorDetails)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Date configuration
    $historicalDays = (Get-Date).Date.ToUniversalTime().AddDays(-$($config.HistoricalDays))
    $futureDays = (Get-Date).Date.ToUniversalTime().AddDays( $($config.FutureDays))
    $importStartDate = $historicalDays.ToString("yyyy-MM-ddTHH:mm:sszzz")
    $importEndDate = $futureDays.ToString("yyyy-MM-ddTHH:mm:sszzz")
    $importStartDateEncoded = [System.Web.HttpUtility]::UrlEncode($importStartDate).ToUpper()
    $importEndDateEncoded = [System.Web.HttpUtility]::UrlEncode($importEndDate).ToUpper()

    # Retrieve authorization token
    $splatRetrieveTokenParams = @{
        Uri         = "$($config.BaseUrl)/laravel/api/v3/oauth/token"
        Method      = 'POST'
        ContentType = 'application/json'
        Body        = @{
            username      = $($config.UserName)
            password      = $($config.Password)
            client_id     = $($config.ClientId)
            client_secret = $($config.ClientSecret)
            grant_type    = 'password'
        } | ConvertTo-Json
    }
    $responseToken = Invoke-RestMethod @splatRetrieveTokenParams
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Bearer $($responseToken.access_token)")

    # Retrieve all shifts (contracts).
    # The response is an object containing two arrays:
    # - One with the fieldNames
    # - One with the actual values
    $rawDatashifts = Invoke-C-QuentialRestMethod -Uri "data-sets/shifts?shownBeginDate=$importStartDateEncoded&shownEndDate=$importEndDateEncoded&include=fields,result" -Headers $headers

    # Combine the data arrays (fields and values) into a single shift object.
    # Add the shift object to a list of shifts, which will be used for searching later.
    $shifts = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rawDatashifts.data.result.rows) {
        $shift = @{}
        for ($i = 0; $i -lt $rawDatashifts.data.fields.Count; $i++) {
            $shift[$rawDatashifts.data.fields[$i].caption] = $row[$i]
        }
        $shifts.Add([PSCustomObject]$shift)
    }

    # Retrieve resources
    $rawDataResources = Invoke-C-QuentialRestMethod -Uri "resources?&include=employment" -Headers $headers

    # Group all resources by UserId
    $rawDataResourcesGroupedByUserId = $rawDataResources.Data | Group-Object {$_.employment.userId}

    # Process data
    foreach ($rawResource in $rawDataResourcesGroupedByUserId) {
        $employeeContracts = [System.Collections.Generic.List[object]]::new()

        # Each resource/employment contains an employeeNumber in the format: 1234/1 or 1234/2.
        # Extract the base part of each employeeNumber by removing everything after the last '/'.
        $employeeNumbers = $rawResource.Group.employment | ForEach-Object { $_.employeeNumber.Substring(0, $_.employeeNumber.LastIndexOf('/')) }

        $personObject = [PSCustomObject]@{
            UserId      = $rawResource.Name
            DisplayName = $rawResource.Group.Name
            ExternalId  = $employeeNumbers | Select-Object -First 1
            Resources   = $rawResource.Group
            Employments = $rawResource.Group.employment
        }

        # Loop through all employments and create a contract object for each one
        $rawResource.Group.employment | ForEach-Object {
            $baseContract  = [PSCustomObject]@{
                ExternalId     = $_.employeeNumber
                BaseExternalId = $_.employeeNumber.Substring(0, $_.employeeNumber.LastIndexOf('/'))
            }

            # Search for all shifts belonging to the employment
            $employmentShifts = $shifts | Where-Object { $_.Personeelsnummer -eq $baseContract.ExternalId }
            $baseContract | Add-Member -MemberType NoteProperty -Name Shifts -Value $employmentShifts
            $employeeContracts.Add($baseContract)
        }

        $personObject | Add-Member -MemberType NoteProperty -name Contracts -Value $employeeContracts
        Write-Output $personObject | ConvertTo-Json -Depth 10
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-C-QuentialError -ErrorObject $ex
        Write-Verbose "Could not import $Name persons. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import $Name persons. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Verbose "Could not import $Name persons. Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import $Name persons. Error: $($errorObj.FriendlyMessage)"
    }
}