function Get-CIMProperties {  
<# 
.SYNOPSIS
  Queries CIM management information for a specific CIM class from a host via WBEM.

.DESCRIPTION
  This function can be used to query CIM information through a generic WBEM Web Request from an ESXi or any other compatible (especially for SFCB daemon based) host system.
  It returns an XML-styled response Object of all properties within the queried CIM class.
  An overview of the available CIM classes in ESXi and more information can be found here: 
  http://pubs.vmware.com/vsphere-55/nav/7_0_2_1_1
  https://www.vmware.com/support/developer/cim-sdk/

.PARAMETER Target
  DNS-Name or IP of the target host.

.PARAMETER Username
  Username to use when authenticating against the target. If not supplied as a parameter, the function will query for user input. The user must have the appropriate permissions to query the CIM interface.
  On ESXi, only assigning the "Host - CIM - CIM Interaction" permission does NOT work, builtin administrator role or a workaround in /etc/security/access.conf is required. See here for more details:
  https://alpacapowered.wordpress.com/2013/09/27/configuring-and-securing-local-esxi-users-for-hardware-monitoring-via-wbem/

.PARAMETER Password
  Password for the user. If not supplied as a parameter, the function will query for user input.

.PARAMETER CIMClassName
  Name of the CIM class to query. By default the "OMC_IPMIIPProtocolEndpoint" class containing information about IPMI-based BMC/ILO/DRAC is queried.

.PARAMETER CIMPort
  TCP port of the CIM daemon on the target host. Default is using port 5989 (sfcb-HTTPS-Daemon on ESXi).

.PARAMETER Secure
  Whether to send the request via plain HTTP or SSL/TLS encrypted HTTPS. Default is encrypted HTTPS. Warning: Disabling will send the credentials in clear text.
  
.OUTPUTS
  Powershell XML Object of the queried CIM properties.

.EXAMPLE
  Get-CIMProperties -Target $Target -Username root
  Asks for a password and queries the host for IPMI-based BMC/ILO/DRAC information (default CIM class OMC_IPMIIPProtocolEndpoint) on default port https/5989.

.EXAMPLE
  (Get-CIMProperties -Target $Target -Username root | ? {$_.NAME -eq 'IPv4Address'}).Value
  Asks for a password just returns the IPv4 address of the BMC/ILO/DRAC interface.

.EXAMPLE
  Get-CIMProperties -Target $Target -Username admin -Password unhackable -CIMClassName OMC_PhysicalMemory -CIMPort 9001
  Returns the host's physical Memory CIM class properties on port https/9001 with username admin and an unhackable password.

.LINK
  https://github.com/alpacacode/Homebrewn-Scripts

.NOTES
  The latest version of this function can be found at Github:
  https://github.com/alpacacode/Homebrewn-Scripts
  Version History: 
  1.0 20.03 2015   - Initial release
 
#Requires -Version 2.0 
#>
  [CmdletBinding()]
  Param(
    [string][parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)] $Target,
    [string]$Username = '',
    [string]$Password = '',
    [string]$CIMClassName = 'OMC_IPMIIPProtocolEndpoint',
    [int]$CIMPort = 5989,
    [bool]$Secure = 1
  )
  
  if ($Username -eq '') {
    $Username = Read-Host "Enter the Username for a local ESXi user who is allowed to query the sfcb daemon CIM stack (e.g. root)"
    Write "Using Username: $Username"
  }
  if ($Password -eq '') {
    [System.Security.SecureString]$Password = Read-Host "Enter the local ESXi User password" -AsSecureString
  }
  else {
    [System.Security.SecureString]$Password = ConvertTo-SecureString -String $Password -AsPlainText -force
  }
  
  #Build the target URI and the base64 [user:password] string to use for the HTTP basic Authentication header
  switch($Secure) {
    $true { $Protocol = 'https' }
    $false { $Protocol = 'http' }
  }
  $URI = [System.Uri]"${Protocol}://${Target}:$CIMPort/cimom"
  $BasicAuth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${Username}:" + ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)))))
  
  #Custom HTTP headers for the Request
  $Headers = @{
    "Authorization" = "Basic $BasicAuth"
    "CIMMethod"= "EnumerateInstances"
    "CIMOperation" = "MethodCall"
    "CIMProtocolVersion" = "1.0"
    "CIMObject" = "root/cimv2"
  }

  #Content of the HTTP POST data
  $POSTBody = [byte[]][char[]]('<?xml version="1.0" encoding="UTF-8"?>
  <CIM CIMVERSION="2.0" DTDVERSION="2.0">
    <MESSAGE ID="882670" PROTOCOLVERSION="1.0">
      <SIMPLEREQ>
        <IMETHODCALL NAME="EnumerateInstances">
          <LOCALNAMESPACEPATH>
            <NAMESPACE NAME="root"/>
            <NAMESPACE NAME="cimv2"/>
          </LOCALNAMESPACEPATH>
          <IPARAMVALUE NAME="ClassName">
            <CLASSNAME NAME="' + $CIMClassName + '"/>
          </IPARAMVALUE>
        </IMETHODCALL>
      </SIMPLEREQ>
    </MESSAGE>
  </CIM>')
  
  #Deterministic pre-check to see if the target can be reached on this port. Only performed if the Test-NetConnection cmdlet is present (only available on Windows 8.1, Windows PowerShell 4.0, Windows Server 2012 R2)
  if((Get-Command Test-NetConnection -errorAction SilentlyContinue) -and (Test-NetConnection $Target -Port $CIMPort -InformationLevel Quiet) -eq $false) {
    Throw "Error: Could not establish a TCP connection to host $Target on port $CIMPort. Make sure the ESXi Firewall permits the connection and the sfcb daemon on the host is running.`n"
  }
 
  #Build the HTTP POST Request with all custom headers
  $Request = [System.Net.HttpWebRequest]::Create($URI)
  $Request.Method = 'POST'
  $Request.ContentType = 'application/xml; charset="utf-8"'
  $Headers.Keys | ForEach-Object { $Request.Headers.Add($_, $Headers[$_]) }
  
  #Disable sending the HTTP Expect header that would cause problems with the POST request and disable server certificate validation
  [System.Net.ServicePointManager]::Expect100Continue = $false
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
  
  #Send the Request and and ensure the response is valid
  Try {
    $Stream = $Request.GetRequestStream();
    $Stream.Write($POSTBody, 0, $POSTBody.Length)
    $Stream.Flush()
    $Stream.Close()
    
    #Read the Response
    $Response = $Request.GetResponse().GetResponseStream()
    $Stream = New-Object System.IO.StreamReader($Response)
    $ResponseTxt = $Stream.ReadToEnd()
    $Stream.Close()
    [xml]$XML = $ResponseTxt
  }
  Catch {
    Throw "Error during CIM Request to $URI with User $Username. Make sure the system is reachable, the username/password is correct and the user is allowed to query CIM information.`n$_.Exception.Message"
  }
  if($ResponseTxt -match '(<ERROR CODE=".+?/>)') {
    Throw "Error: The server CIM response contains an error:" + $matches[1] + "`nThe full server response was:`n$ResponseTxt"
  } 
  Return $XML.CIM.MESSAGE.SIMPLERSP.IMETHODRESPONSE.IRETURNVALUE.'VALUE.NAMEDINSTANCE'.INSTANCE.PROPERTY
}