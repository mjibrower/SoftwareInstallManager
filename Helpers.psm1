﻿function Start-Log
{
	<#
	.SYNOPSIS
		This function creates the initial log file and sets a few global variables
		that are common among the session.  Call this function at the very top of your
		installer script.

	.PARAMETER  FilePath
		The file path where you'd like to place the log file on the file system.  If no file path
		specified, it will create a file in the system's temp directory named the same as the script
		which called this function with a .log extension.

	.EXAMPLE
		PS C:\> Start-Log -FilePath 'C:\Temp\installer.log

	.NOTES

	#>
	[CmdletBinding()]
	param (
		[ValidateScript({ Split-Path $_ -Parent | Test-Path })]
		[string]$FilePath = "$(Get-SystemTempFolderPath)\$((Get-Date -f 'MM-dd-yyyy (hhmm tt)') + 'Software.log')"
	)
	
	try
	{
		if (!(Test-Path $FilePath))
		{
			## Create the log file
			New-Item $FilePath -Type File | Out-Null
		}
		
		## Set the global variable to be used as the FilePath for all subsequent Write-Log
		## calls in this session
		$global:ScriptLogFilePath = $FilePath
	}
	catch
	{
		Write-Error $_.Exception.Message
	}
}

function Write-Log
{
	<#
	.SYNOPSIS
		This function creates or appends a line to a log file

	.DESCRIPTION
		This function writes a log line to a log file in the form synonymous with 
		ConfigMgr logs so that tools such as CMtrace and SMStrace can easily parse 
		the log file.  It uses the ConfigMgr client log format's file section
		to add the line of the script in which it was called.

	.PARAMETER  Message
		The message parameter is the log message you'd like to record to the log file

	.PARAMETER  LogLevel
		The logging level is the severity rating for the message you're recording. Like ConfigMgr
		clients, you have 3 severity levels available; 1, 2 and 3 from informational messages
		for FYI to critical messages that stop the install. This defaults to 1.

	.EXAMPLE
		PS C:\> Write-Log -Message 'Value1' -LogLevel 'Value2'
		This example shows how to call the Write-Log function with named parameters.

	.NOTES

	#>
	[CmdletBinding()]
	param (
		[Parameter(
				   Mandatory = $true)]
		[string]$Message,
		
		[Parameter()]
		[ValidateSet(1, 2, 3)]
		[int]$LogLevel = 1
	)
	
	try
	{
		$TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
		## Build the line which will be recorded to the log file
		$Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
		$LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $LogLevel
		$Line = $Line -f $LineFormat
		
		if (-not (Test-Path Variable:\ScriptLogFilePath))
		{
			Write-Verbose $Message
		}
		else
		{
			Add-Content -Value $Line -Path $ScriptLogFilePath
		}
	}
	catch
	{
		Write-Error $_.Exception.Message
	}
}

function Test-Error
{
	<#
	.SYNOPSIS
		This function is used after the execution of any script snippet.  It is used as a standardized output
		method to log either an error or a success.
	.PARAMETER MyError
		The System.Exception object type error typically thrown in a try/catch block
	.PARAMETER SuccessString
		If no error is found, this will be logged.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$MyError,
		
		[Parameter()]
		[string]$SuccessString
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			if (!$MyError)
			{
				Write-Log -Message $SuccessString
				$true
			}
			else
			{
				throw $MyError
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Convert-CompressedGuidToGuid
{
	<#
	.SYNOPSIS
		This converts a compressed GUID also known as a product code into a GUID.	
	.DESCRIPTION
		This function will typically be used to figure out the MSI installer GUID
		that matches up with the product code stored in the 'SOFTWARE\Classes\Installer\Products'
		registry path.
	.EXAMPLE
		Convert-CompressedGuidToGuid -CompressedGuid '2820F6C7DCD308A459CABB92E828C144'
	
		This example would output the GUID '{7C6F0282-3DCD-4A80-95AC-BB298E821C44}'
	.PARAMETER CompressedGuid
		The compressed GUID you'd like to convert.
	#>
	[CmdletBinding()]
	[OutputType([System.String])]
	param (
		[Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
		[ValidatePattern('^[0-9a-fA-F]{32}$')]
		[string]$CompressedGuid
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$Indexes = [ordered]@{
				0 = 8;
				8 = 4;
				12 = 4;
				16 = 2;
				18 = 2;
				20 = 2;
				22 = 2;
				24 = 2;
				26 = 2;
				28 = 2;
				30 = 2
			}
			$Guid = '{'
			foreach ($index in $Indexes.GetEnumerator())
			{
				$part = $CompressedGuid.Substring($index.Key, $index.Value).ToCharArray()
				[array]::Reverse($part)
				$Guid += $part -join ''
			}
			$Guid = $Guid.Insert(9, '-').Insert(14, '-').Insert(19, '-').Insert(24, '-')
			$Guid + '}'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Convert-GuidToCompressedGuid
{
	<#
	.SYNOPSIS
		This converts a GUID to a compressed GUID also known as a product code.	
	.DESCRIPTION
		This function will typically be used to figure out the product code
		that matches up with the product code stored in the 'SOFTWARE\Classes\Installer\Products'
		registry path to a MSI installer GUID.
	.EXAMPLE
		Convert-GuidToCompressedGuid -Guid '{7C6F0282-3DCD-4A80-95AC-BB298E821C44}'
	
		This example would output the compressed GUID '2820F6C7DCD308A459CABB92E828C144'
	.PARAMETER Guid
		The GUID you'd like to convert.
	#>
	[CmdletBinding()]
	[OutputType()]
	param (
		[Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
		[string]$Guid
	)
	begin
	{
		$Guid = $Guid.Replace('-', '').Replace('{', '').Replace('}', '')
	}
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$Groups = @(
			$Guid.Substring(0, 8).ToCharArray(),
			$Guid.Substring(8, 4).ToCharArray(),
			$Guid.Substring(12, 4).ToCharArray(),
			$Guid.Substring(16, 16).ToCharArray()
			)
			$Groups[0..2] | foreach {
				[array]::Reverse($_)
			}
			$CompressedGuid = ($Groups[0..2] | foreach { $_ -join '' }) -join ''
			
			$chararr = $Groups[3]
			for ($i = 0; $i -lt $chararr.count; $i++)
			{
				if (($i % 2) -eq 0)
				{
					$CompressedGuid += ($chararr[$i + 1] + $chararr[$i]) -join ''
				}
			}
			$CompressedGuid
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Convert-ToUncPath
{
	<#
	.SYNOPSIS
		A simple function to convert a local file path and a computer name to a network UNC path.
	.PARAMETER LocalFilePath
		A file path ie. C:\Windows\somefile.txt
	.PARAMETER Computername
		The computer in which the file path exists on
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$LocalFilePath,
		
		[Parameter()]
		[string]$Computername
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$RemoteFilePathDrive = ($LocalFilePath | Split-Path -Qualifier).TrimEnd(':')
			"\\$Computername\$RemoteFilePathDrive`$$($LocalFilePath | Split-Path -NoQualifier)"
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-32BitProgramFilesPath
{
	<#
	.SYNOPSIS
		On x64 machines the x86 program files path is Program Files (x86) while on x86 machines it's just Program Files.  This function
		does that decision for you and just outputs the x86 program files path regardless of OS architecture
	#>
	[CmdletBinding()]
	param ()
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			if ((Get-Architecture) -eq 'x64')
			{
				${env:ProgramFiles(x86)}
			}
			else
			{
				$env:ProgramFiles
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-32BitRegistrySoftwarePath
{
	<#
	.SYNOPSIS
		On x64 machines the x86 Software registry key path is HKLM:\SOFTWARE\Wow6432Node while on x86 machines it's just 
		HKLM:\Software. This function does that decision for you and just outputs the x86 path regardless of OS architecture.
	.PARAMETER Scope
		Specify either HKLM or HKCU.  Defaults to HKLM.
	#>
	[CmdletBinding()]
	param (
		[ValidateSet('HKLM', 'HKCU')]
		[string]$Scope = 'HKLM'
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			if ((Get-Architecture) -eq 'x64')
			{
				"$Scope`:\SOFTWARE\Wow6432Node"
			}
			else
			{
				"$Scope`:\SOFTWARE"
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-Architecture
{
	<#
	.SYNOPSIS
		This simple function tells you whether the machine you're running on is either x64 or x86
	#>
	[CmdletBinding()]
	param ()
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			if ([System.Environment]::Is64BitOperatingSystem -or ((Get-WmiObject -Class Win32_ComputerSystem | select -ExpandProperty SystemType) -eq 'x64-based PC'))
			{
				'x64'
			}
			else
			{
				'x86'
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-Count
{
	<#
	.SYNOPSIS
		This function was created to account for collections where the output from a command
		is 1 and simply using .Count doesn't work well.
	#>
	param (
		[Parameter(ValueFromPipeline = $true)]
		$Value
	)
	process
	{
		Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
		if (!$Input)
		{
			0
		}
		else
		{
			$count = $Input.Count
			$count
		}
		Write-Log -Message "$($MyInvocation.MyCommand) - END"
	}
}

function Get-DriveFreeSpace
{
	<#
	.SYNOPSIS
		This finds the total hard drive free space for one or multiple hard drive partitions
	.DESCRIPTION
		This finds the total hard drive free space for one or multiple hard drive partitions. It returns free space
		rounded to the nearest SizeOutputLabel parameter
	.PARAMETER  DriveLetter
		This is the drive letter of the hard drive partition you'd like to query. By default, all drive letters are queried.
	.PARAMETER  SizeOutputLabel
		In what size increments you'd like the size returned (KB, MB, GB, TB). Defaults to MB.
	.PARAMETER  Computername
		The computername(s) you'd like to find free space on.  This defaults to the local machine.
	.EXAMPLE
		PS C:\> Get-DriveFreeSpace -DriveLetter 'C','D'
		This example retrieves the free space on the C and D drive partition.
	#>
	[CmdletBinding()]
	[OutputType([array])]
	param
	(
		[string[]]$Computername = 'localhost',
		
		[Parameter(ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true)]
		[ValidatePattern('[A-Z]')]
		[string]$DriveLetter,
		
		[ValidateSet('KB', 'MB', 'GB', 'TB')]
		[string]$SizeOutputLabel = 'MB'
		
	)
	
	Begin
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			$WhereQuery = "SELECT FreeSpace,DeviceID FROM Win32_Logicaldisk"
			
			if ($PsBoundParameters.DriveLetter)
			{
				$WhereQuery += ' WHERE'
				$BuiltQueryParams = { @() }.Invoke()
				foreach ($Letter in $DriveLetter)
				{
					$BuiltQueryParams.Add("DeviceId = '$DriveLetter`:'")
				}
				$WhereQuery = "$WhereQuery $($BuiltQueryParams -join ' OR ')"
			}
			Write-Debug "Using WQL query $WhereQuery"
			$WmiParams = @{
				'Query' = $WhereQuery
				'ErrorVariable' = 'MyError';
				'ErrorAction' = 'SilentlyContinue'
			}
		}
		catch
		{
			Write-Log -Message $_.Exception.Message -LogLevel '3'
		}
	}
	Process
	{
		try
		{
			foreach ($Computer in $Computername)
			{
				try
				{
					$WmiParams.Computername = $Computer
					$WmiResult = Get-WmiObject @WmiParams
					if (!(Test-Error $MyError "Sucessfull WMI query"))
					{
						throw $MyError
					}
					elseif (!$WmiResult)
					{
						throw "Drive letter does not exist on target system"
					}
					foreach ($Result in $WmiResult)
					{
						if ($Result.Freespace)
						{
							[pscustomobject]@{
								'Computername' = $Computer;
								'DriveLetter' = $Result.DeviceID;
								'Freespace' = [int]($Result.FreeSpace / "1$SizeOutputLabel")
							}
						}
					}
				}
				catch
				{
					Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
					$false
				}
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-InstallerType
{
	<#
	.SYNOPSIS
		Based on the uninstall string retrieved from the registry this function will tell you what kind of installer was
		used to install the product.  This information is helpful when figuring out the best way to remove software.
	
	.PARAMETER UninstallString
		The uninstall string that's stored in the HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\%GUID% UninstallString
		registry value.
	#>
	[CmdletBinding()]
	param (
		[string]$UninstallString
	)
	
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			if ($UninstallString -imatch 'msiexec.exe')
			{
				'Windows Installer'
			}
			elseif ($UninstallString -imatch 'InstallShield Installation')
			{
				'InstallShield'
			}
			else
			{
				$false
			}
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}

function Get-LoggedOnUserSID
{
	<#
	.SYNOPSIS
		This function queries the registry to find the SID of the user that's currently logged onto the computer interactively.
	#>
	[CmdletBinding()]
	param ()
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			
			if (-not (Get-PSDrive -Name 'HKU' -ErrorAction SilentlyContinue))
			{
				New-PSDrive -Name HKU -PSProvider Registry -Root Registry::HKEY_USERS | Out-Null
				## Every user that's logged on has a registry key in HKU with their SID
				(Get-ChildItem HKU: | where { $_.Name -match 'S-\d-\d+-(\d+-){1,14}\d+$' }).PSChildName
			}
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			$false
		}
		finally
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
	}
}

function Get-OperatingSystem
{
	<#
	.SYNOPSIS
		This function queries the operating system name from WMI.
	.DESCRIPTION
		Using a WMI query, this function uses the Win32_OperatingSystem WMI class
		to output the operating system running on $Computername
	.PARAMETER Computername
		The name of the computer to query.  This defaults to the local host.
	.EXAMPLE
		PS C:\> Get-OperatingSystem -Computername MYCOMPUTER
		
		This example finds the operating system on a computer named MYCOMPUTER
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$Computername = 'localhost'
	)
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			(Get-WmiObject -ComputerName $Computername -Query 'SELECT Caption FROM Win32_OperatingSystem').Caption
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			$false
		}
		finally
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
	}
}

function Get-SystemTempFolderPath
{
	<#
	.SYNOPSIS
		This function uses the TEMP system environment variable to easily discover the folder path
		to the system's temp folder
	#>
	[CmdletBinding()]
	param ()
	process
	{
		try
		{
			Write-Log -Message "$($MyInvocation.MyCommand) - BEGIN"
			[environment]::GetEnvironmentVariable('TEMP', 'Machine')
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
		}
		catch
		{
			Write-Log -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)" -LogLevel '3'
			Write-Log -Message "$($MyInvocation.MyCommand) - END"
			$false
		}
	}
}