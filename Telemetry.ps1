﻿# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# Singleton. Don't directly access this though....always get it
# by calling Get-BaseTelemetryEvent to ensure that it has been initialized and that you're always
# getting a fresh copy.
$script:GHBaseTelemetryEvent = $null

function Get-PiiSafeString
{
<#
    .SYNOPSIS
        If PII protection is enabled, returns back an SHA512-hashed value for the specified string,
        otherwise returns back the original string, untouched.

    .SYNOPSIS
        If PII protection is enabled, returns back an SHA512-hashed value for the specified string,
        otherwise returns back the original string, untouched.

        The Git repo for this module can be found here: http://aka.ms/PowerShellForGitHub

    .PARAMETER PlainText
        The plain text that contains PII that may need to be protected.

    .EXAMPLE
        Get-PiiSafeString -PlainText "Hello World"

        Returns back the string "B10A8DB164E0754105B7A99BE72E3FE5" which respresents
        the SHA512 hash of "Hello World", but only if the "DisablePiiProtection" configuration
        value is $false.  If it's $true, "Hello World" will be returned.

    .OUTPUTS
        System.String - A SHA512 hash of PlainText will be returned if the "DisablePiiProtection"
                        configuration value is $false, otherwise PlainText will be returned untouched.
#>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $PlainText
    )

    if (Get-GitHubConfiguration -Name DisablePiiProtection)
    {
        return $PlainText
    }
    else
    {
        return (Get-SHA512Hash -PlainText $PlainText)
    }
}

function Get-TelemetryClient
{
<#
    .SYNOPSIS
        Returns back the singleton instance of the Application Insights TelemetryClient for
        this module.

    .DESCRIPTION
        Returns back the singleton instance of the Application Insights TelemetryClient for
        this module.

        If the singleton hasn't been initialized yet, this will ensure all dependenty assemblies
        are available on the machine, create the client and initialize its properties.

        This will first look for the dependent assemblies in the module's script directory.

        Next it will look for the assemblies in the location defined by
        $SBAlternateAssemblyDir.  This value would have to be defined by the user
        prior to execution of this cmdlet.

        If not found there, it will look in a temp folder established during this
        PowerShell session.

        If still not found, it will download the nuget package
        for it to a temp folder accessible during this PowerShell session.

        The Git repo for this module can be found here: http://aka.ms/PowerShellForGitHub

    .PARAMETER NoStatus
        If this switch is specified, long-running commands will run on the main thread
        with no commandline status update.  When not specified, those commands run in
        the background, enabling the command prompt to provide status information.

    .EXAMPLE
        Get-TelemetryClient

        Returns back the singleton instance to the TelemetryClient for the module.
        If any nuget packages have to be downloaded in order to load the TelemetryClient, the
        command prompt will show a time duration status counter during the download process.

    .EXAMPLE
        Get-TelemetryClient -NoStatus

        Returns back the singleton instance to the TelemetryClient for the module.
        If any nuget packages have to be downloaded in order to load the TelemetryClient, the
        command prompt will appear to hang during this time.

    .OUTPUTS
        Microsoft.ApplicationInsights.TelemetryClient
#>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "", Justification="Methods called within here make use of PSShouldProcess, and the switch is passed on to them inherently.")]
    param(
        [switch] $NoStatus
    )

    if ($null -eq $script:GHTelemetryClient)
    {
        if (-not (Get-GitHubConfiguration -Name SuppressTelemetryReminder))
        {
            Write-Log -Message 'Telemetry is currently enabled.  It can be disabled by calling "Set-GitHubConfiguration -DisableTelemetry". Refer to USAGE.md#telemetry for more information. Stop seeing this message in the future by calling "Set-GitHubConfiguration -SuppressTelemetryReminder".'
        }

        Write-Log -Message "Initializing telemetry client." -Level Verbose

        $dlls = @(
                    (Get-ThreadingTasksDllPath -NoStatus:$NoStatus),
                    (Get-DiagnosticsTracingDllPath -NoStatus:$NoStatus),
                    (Get-ApplicationInsightsDllPath -NoStatus:$NoStatus)
        )

        foreach ($dll in $dlls)
        {
            $bytes = [System.IO.File]::ReadAllBytes($dll)
            [System.Reflection.Assembly]::Load($bytes) | Out-Null
        }

        $username = Get-PiiSafeString -PlainText $env:USERNAME

        $script:GHTelemetryClient = New-Object Microsoft.ApplicationInsights.TelemetryClient
        $script:GHTelemetryClient.InstrumentationKey = (Get-GitHubConfiguration -Name ApplicationInsightsKey)
        $script:GHTelemetryClient.Context.User.Id = $username
        $script:GHTelemetryClient.Context.Session.Id = [System.GUID]::NewGuid().ToString()
        $script:GHTelemetryClient.Context.Properties['Username'] = $username
        $script:GHTelemetryClient.Context.Properties['DayOfWeek'] = (Get-Date).DayOfWeek
        $script:GHTelemetryClient.Context.Component.Version = $MyInvocation.MyCommand.Module.Version.ToString()
    }

    return $script:GHTelemetryClient
}

function Get-BaseTelemetryEvent
{
    <#
    .SYNOPSIS
        Returns back the base object for an Application Insights telemetry event.

    .DESCRIPTION
        Returns back the base object for an Application Insights telemetry event.

        The Git repo for this module can be found here: http://aka.ms/PowerShellForGitHub

    .EXAMPLE
        Get-BaseTelemetryEvent

        Returns back a base telemetry event, populated with the minimum properties necessary
        to correctly report up to this project's telemetry.  Callers can then add on to the
        event as nececessary.

    .OUTPUTS
        [PSCustomObject]
#>
    [CmdletBinding()]
    param()

    if ($null -eq $script:GHBaseTelemetryEvent)
    {
        $username = Get-PiiSafeString -PlainText $env:USERNAME

        $script:GHBaseTelemetryEvent = [PSCustomObject] @{
            'name' = 'Microsoft.ApplicationInsights.66d83c523070489b886b09860e05e78a.Event'
            'time' = (Get-Date).ToUniversalTime().ToString("O")
            'iKey' = (Get-GitHubConfiguration -Name ApplicationInsightsKey)
            'tags' = [PSCustomObject] @{
                'ai.user.id' = $username
                'ai.session.id' = [System.GUID]::NewGuid().ToString()
                'ai.application.ver' = $MyInvocation.MyCommand.Module.Version.ToString()
                'ai.internal.sdkVersion' = '2.0.1.33027' # The version this schema was based off of.
            }

            'data' = [PSCustomObject] @{
                'baseType' = 'EventData'
                'baseData' = [PSCustomObject] @{
                    'ver' = 2
                    'properties' = [PSCustomObject] @{
                        'DayOfWeek' = (Get-Date).DayOfWeek
                        'Username' = $username
                    }
                }
            }
        }
    }

    return $script:GHBaseTelemetryEvent.PSObject.Copy() # Get a new instance, not a reference
}

function Invoke-SendTelemetryEvent
{
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "", Justification="We use global variables sparingly and intentionally for module configuration, and employ a consistent naming convention.")]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject] $TelemetryEvent,

        [switch] $NoStatus
    )

    $jsonConversionDepth = 20 # Seems like it should be more than sufficient
    $uri = 'https://dc.services.visualstudio.com/v2/track'
    $method = 'POST'
    $headers = @{'Content-Type' = 'application/json; charset=UTF-8'}

    $body = ConvertTo-Json -InputObject $TelemetryEvent -Depth $jsonConversionDepth
    $bodyAsBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    try
    {
        Write-Log -Message "Sending telemetry event data to $uri [Timeout = $(Get-GitHubConfiguration -Name WebRequestTimeoutSec))]" -Level Verbose

        $NoStatus = Resolve-ParameterWithDefaultConfigurationValue -Name NoStatus -ConfigValueName DefaultNoStatus
        if ($NoStatus)
        {
            if ($PSCmdlet.ShouldProcess($url, "Invoke-WebRequest"))
            {
                $params = @{}
                $params.Add("Uri", $uri)
                $params.Add("Method", $method)
                $params.Add("Headers", $headers)
                $params.Add("UseDefaultCredentials", $true)
                $params.Add("UseBasicParsing", $true)
                $params.Add("TimeoutSec", (Get-GitHubConfiguration -Name WebRequestTimeoutSec))
                $params.Add("Body", $bodyAsBytes)

                $result = Invoke-WebRequest @params
            }
        }
        else
        {
            $jobName = "Invoke-SendTelemetryEvent-" + (Get-Date).ToFileTime().ToString()

            if ($PSCmdlet.ShouldProcess($jobName, "Start-Job"))
            {
                [scriptblock]$scriptBlock = {
                    param($Uri, $Method, $Headers, $BodyAsBytes, $TimeoutSec, $ScriptRootPath)

                    # We need to "dot invoke" Helpers.ps1 and GitHubConfiguration.ps1 within
                    # the context of this script block since we're running in a different
                    # PowerShell process and need access to Get-HttpWebResponseContent and
                    # config values referenced within Write-Log.
                    . (Join-Path -Path $ScriptRootPath -ChildPath 'Helpers.ps1')
                    . (Join-Path -Path $ScriptRootPath -ChildPath 'GitHubConfiguration.ps1')

                    $params = @{}
                    $params.Add("Uri", $Uri)
                    $params.Add("Method", $Method)
                    $params.Add("Headers", $Headers)
                    $params.Add("UseDefaultCredentials", $true)
                    $params.Add("UseBasicParsing", $true)
                    $params.Add("TimeoutSec", $TimeoutSec)
                    $params.Add("Body", $BodyAsBytes)

                    try
                    {
                        Invoke-WebRequest @params
                    }
                    catch [System.Net.WebException]
                    {
                        # We need to access certain headers in the exception handling,
                        # but the actual *values* of the headers of a WebException don't get serialized
                        # when the RemoteException wraps it.  To work around that, we'll extract the
                        # information that we actually care about *now*, and then we'll throw our own exception
                        # that is just a JSON object with the data that we'll later extract for processing in
                        # the main catch.
                        $ex = @{}
                        $ex.Message = $_.Exception.Message
                        $ex.StatusCode = $_.Exception.Response.StatusCode
                        $ex.StatusDescription = $_.Exception.Response.StatusDescription
                        $ex.InnerMessage = $_.ErrorDetails.Message
                        try
                        {
                            $ex.RawContent = Get-HttpWebResponseContent -WebResponse $_.Exception.Response
                        }
                        catch
                        {
                            Write-Log -Message "Unable to retrieve the raw HTTP Web Response:" -Exception $_ -Level Warning
                        }

                        $jsonConversionDepth = 20 # Seems like it should be more than sufficient
                        throw (ConvertTo-Json -InputObject $ex -Depth $jsonConversionDepth)
                    }
                }

                $null = Start-Job -Name $jobName -ScriptBlock $scriptBlock -Arg @(
                    $uri,
                    $method,
                    $headers,
                    $bodyAsBytes,
                    (Get-GitHubConfiguration -Name WebRequestTimeoutSec),
                    $PSScriptRoot)

                if ($PSCmdlet.ShouldProcess($jobName, "Wait-JobWithAnimation"))
                {
                    $description = 'Sending telemetry data'
                    Wait-JobWithAnimation -Name $jobName -Description $Description
                }

                if ($PSCmdlet.ShouldProcess($jobName, "Receive-Job"))
                {
                    $result = Receive-Job $jobName -AutoRemoveJob -Wait -ErrorAction SilentlyContinue -ErrorVariable remoteErrors
                }
            }

            if ($remoteErrors.Count -gt 0)
            {
                throw $remoteErrors[0].Exception
            }
        }

        return $result
    }
    catch
    {
        # We only know how to handle WebExceptions, which will either come in "pure" when running with -NoStatus,
        # or will come in as a RemoteException when running normally (since it's coming from the asynchronous Job).
        $ex = $null
        $message = $null
        $statusCode = $null
        $statusDescription = $null
        $innerMessage = $null
        $rawContent = $null

        if ($_.Exception -is [System.Net.WebException])
        {
            $ex = $_.Exception
            $message = $_.Exception.Message
            $statusCode = $ex.Response.StatusCode.value__ # Note that value__ is not a typo.
            $statusDescription = $ex.Response.StatusDescription
            $innerMessage = $_.ErrorDetails.Message
            try
            {
                $rawContent = Get-HttpWebResponseContent -WebResponse $ex.Response
            }
            catch
            {
                Write-Log -Message "Unable to retrieve the raw HTTP Web Response:" -Exception $_ -Level Warning
            }
        }
        elseif (($_.Exception -is [System.Management.Automation.RemoteException]) -and
            ($_.Exception.SerializedRemoteException.PSObject.TypeNames[0] -eq 'Deserialized.System.Management.Automation.RuntimeException'))
        {
            $ex = $_.Exception
            try
            {
                $deserialized = $ex.Message | ConvertFrom-Json
                $message = $deserialized.Message
                $statusCode = $deserialized.StatusCode
                $statusDescription = $deserialized.StatusDescription
                $innerMessage = $deserialized.InnerMessage
                $rawContent = $deserialized.RawContent
            }
            catch [System.ArgumentException]
            {
                # Will be thrown if $ex.Message isn't JSON content
                Write-Log -Exception $_ -Level Error
                throw
            }
        }
        else
        {
            Write-Log -Exception $_ -Level Error
            throw
        }

        $output = @()
        $output += $message

        if (-not [string]::IsNullOrEmpty($statusCode))
        {
            $output += "$statusCode | $($statusDescription.Trim())"
        }

        if (-not [string]::IsNullOrEmpty($innerMessage))
        {
            try
            {
                $innerMessageJson = ($innerMessage | ConvertFrom-Json)
                if ($innerMessageJson -is [String])
                {
                    $output += $innerMessageJson.Trim()
                }
                elseif (-not [String]::IsNullOrWhiteSpace($innerMessageJson.message))
                {
                    $output += "$($innerMessageJson.message.Trim()) | $($innerMessageJson.documentation_url.Trim())"
                    if ($innerMessageJson.details)
                    {
                        $output += "$($innerMessageJson.details | Format-Table | Out-String)"
                    }
                }
                else
                {
                    # In this case, it's probably not a normal message from the API
                    $output += ($innerMessageJson | Out-String)
                }
            }
            catch [System.ArgumentException]
            {
                # Will be thrown if $innerMessage isn't JSON content
                $output += $innerMessage.Trim()
            }
        }

        # It's possible that the API returned JSON content in its error response.
        if (-not [String]::IsNullOrWhiteSpace($rawContent))
        {
            $output += $rawContent
        }

        if (-not [String]::IsNullOrEmpty($requestId))
        {
            $localTelemetryProperties['RequestId'] = $requestId
            $message = 'RequestId: ' + $requestId
            $output += $message
            Write-Log -Message $message -Level Verbose
        }

        $newLineOutput = ($output -join [Environment]::NewLine)
        Write-Log -Message $newLineOutput -Level Error
        throw $newLineOutput
    }
}

function Set-TelemetryEvent
{
<#
    .SYNOPSIS
        Posts a new telemetry event for this module to the configured Applications Insights instance.

    .DESCRIPTION
        Posts a new telemetry event for this module to the configured Applications Insights instance.

        The Git repo for this module can be found here: http://aka.ms/PowerShellForGitHub

    .PARAMETER EventName
        The name of the event that has occurred.

    .PARAMETER Properties
        A collection of name/value pairs (string/string) that should be associated with this event.

    .PARAMETER Metrics
        A collection of name/value pair metrics (string/double) that should be associated with
        this event.

    .PARAMETER NoStatus
        If this switch is specified, long-running commands will run on the main thread
        with no commandline status update.  When not specified, those commands run in
        the background, enabling the command prompt to provide status information.

    .EXAMPLE
        Set-TelemetryEvent "zFooTest1"

        Posts a "zFooTest1" event with the default set of properties and metrics.  If the telemetry
        client needs to be created to accomplish this, and the required assemblies are not available
        on the local machine, the download status will be presented at the command prompt.

    .EXAMPLE
        Set-TelemetryEvent "zFooTest1" @{"Prop1" = "Value1"}

        Posts a "zFooTest1" event with the default set of properties and metrics along with an
        additional property named "Prop1" with a value of "Value1".  If the telemetry client
        needs to be created to accomplish this, and the required assemblies are not available
        on the local machine, the download status will be presented at the command prompt.

    .EXAMPLE
        Set-TelemetryEvent "zFooTest1" -NoStatus

        Posts a "zFooTest1" event with the default set of properties and metrics.  If the telemetry
        client needs to be created to accomplish this, and the required assemblies are not available
        on the local machine, the command prompt will appear to hang while they are downloaded.

    .NOTES
        Because of the short-running nature of this module, we always "flush" the events as soon
        as they have been posted to ensure that they make it to Application Insights.
#>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "", Justification="Methods called within here make use of PSShouldProcess, and the switch is passed on to them inherently.")]
    param(
        [Parameter(Mandatory)]
        [string] $EventName,

        [hashtable] $Properties = @{},

        [hashtable] $Metrics = @{},

        [switch] $NoStatus
    )

    if (Get-GitHubConfiguration -Name DisableTelemetry)
    {
        Write-Log -Message "Telemetry has been disabled via configuration. Skipping reporting event [$EventName]." -Level Verbose
        return
    }

    Write-InvocationLog -ExcludeParameter @('Properties', 'Metrics')

    try
    {
        $telemetryEvent = Get-BaseTelemetryEvent

        Add-Member -InputObject $telemetryEvent.data.baseData -Name 'name' -Value $EventName -MemberType NoteProperty -Force

        # Properties
        foreach ($property in $Properties.GetEnumerator())
        {
            Add-Member -InputObject $telemetryEvent.data.baseData.properties -Name $property.Key -Value $property.Value -MemberType NoteProperty -Force
        }

        # Measurements
        if ($Metrics.Count -gt 0)
        {
            $measurements = @{}
            foreach ($metric in $Metrics.GetEnumerator())
            {
                $measurements[$metric.Key] = $metric.Value
            }

            Add-Member -InputObject $telemetryEvent.data.baseData -Name 'measurements' -Value ([PSCustomObject] $measurements) -MemberType NoteProperty -Force
        }

        Invoke-SendTelemetryEvent -TelemetryEvent $telemetryEvent -NoStatus:$NoStatus
    }
    catch
    {
        Write-Log -Level Warning -Exception $_ -Message @(
            "Encountered a problem while trying to record telemetry events.",
            "This is non-fatal, but it would be helpful if you could report this problem",
            "to the PowerShellForGitHub team for further investigation:")
    }
}

function Set-TelemetryException
{
<#
    .SYNOPSIS
        Posts a new telemetry event to the configured Application Insights instance indicating
        that an exception occurred in this this module.

    .DESCRIPTION
        Posts a new telemetry event to the configured Application Insights instance indicating
        that an exception occurred in this this module.

        The Git repo for this module can be found here: http://aka.ms/PowerShellForGitHub

    .PARAMETER Exception
        The exception that just occurred.

    .PARAMETER ErrorBucket
        A property to be added to the Exception being logged to make it easier to filter to
        exceptions resulting from similar scenarios.

    .PARAMETER Properties
        Additional properties that the caller may wish to be associated with this exception.

    .PARAMETER NoFlush
        It's not recommended to use this unless the exception is coming from Flush-TelemetryClient.
        By default, every time a new exception is logged, the telemetry client will be flushed
        to ensure that the event is published to the Application Insights.  Use of this switch
        prevents that automatic flushing (helpful in the scenario where the exception occurred
        when trying to do the actual Flush).

    .PARAMETER NoStatus
        If this switch is specified, long-running commands will run on the main thread
        with no commandline status update.  When not specified, those commands run in
        the background, enabling the command prompt to provide status information.

    .EXAMPLE
        Set-TelemetryException $_

        Used within the context of a catch statement, this will post the exception that just
        occurred, along with a default set of properties.  If the telemetry client needs to be
        created to accomplish this, and the required assemblies are not available on the local
        machine, the download status will be presented at the command prompt.

    .EXAMPLE
        Set-TelemetryException $_ -NoStatus

        Used within the context of a catch statement, this will post the exception that just
        occurred, along with a default set of properties.  If the telemetry client needs to be
        created to accomplish this, and the required assemblies are not available on the local
        machine, the command prompt will appear to hang while they are downloaded.

    .NOTES
        Because of the short-running nature of this module, we always "flush" the events as soon
        as they have been posted to ensure that they make it to Application Insights.
#>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "", Justification="Methods called within here make use of PSShouldProcess, and the switch is passed on to them inherently.")]
    param(
        [Parameter(Mandatory)]
        [System.Exception] $Exception,

        [string] $ErrorBucket,

        [hashtable] $Properties = @{},

        [switch] $NoStatus
    )

    $global:howard = $Exception
    return

    if (Get-GitHubConfiguration -Name DisableTelemetry)
    {
        Write-Log -Message "Telemetry has been disabled via configuration. Skipping reporting exception." -Level Verbose
        return
    }

    Write-InvocationLog -ExcludeParameter @('Exception', 'Properties', 'NoFlush')

    try
    {
        $telemetryEvent = Get-BaseTelemetryEvent

        $telemetryEvent.data.baseType = 'ExceptionData'
        Add-Member -InputObject $telemetryEvent.data.baseData -Name 'handledAt' -Value 'UserCode' -MemberType NoteProperty -Force

        # Properties
        if (-not [String]::IsNullOrWhiteSpace($ErrorBucket))
        {
            Add-Member -InputObject $telemetryEvent.data.baseData.properties -Name 'ErrorBucket' -Value $ErrorBucket -MemberType NoteProperty -Force
        }

        Add-Member -InputObject $telemetryEvent.data.baseData.properties -Name 'Message' -Value $Exception.Message -MemberType NoteProperty -Force
        Add-Member -InputObject $telemetryEvent.data.baseData.properties -Name 'HResult' -Value ("0x{0}" -f [Convert]::ToString($Exception.HResult, 16)) -MemberType NoteProperty -Force
        foreach ($property in $Properties.GetEnumerator())
        {
            Add-Member -InputObject $telemetryEvent.data.baseData.properties -Name $property.Key -Value $property.Value -MemberType NoteProperty -Force
        }

        # Exception data
        $exceptionData = [PSCustomObject] @{
            'id' = 1
            'typeName' = 'foo'
        }

        $exceptions = @($exceptionData)
        Add-Member -InputObject $telemetryEvent.data.baseData -Name 'exceptions' -Value ([PSCustomObject] $exceptions) -MemberType NoteProperty -Force

        Invoke-SendTelemetryEvent -TelemetryEvent $telemetryEvent -NoStatus:$NoStatus
    }
    catch
    {
        Write-Log -Level Warning -Exception $_ -Message @(
            "Encountered a problem while trying to record telemetry events.",
            "This is non-fatal, but it would be helpful if you could report this problem",
            "to the PowerShellForGitHub team for further investigation:")
    }
}
