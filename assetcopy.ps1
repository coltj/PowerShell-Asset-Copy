#######################################################################################################################
##Author : Colt Johnson																			
##Purpose: Automation script to copy assets from a master folder to a project's folder
#######################################################################################################################
##
## Purpose: This script will scan a directory, looking for files of a specific format. It will open each file and parse
##			it, looking for occurrences of lines with the correct file extensions, as determined in $extensionArray.
##			The script will extract all of the filenames and check to see if any files are missing from a project.
##			It will also check to see if any of the existing files are out of date, and then copy the correct
##			files to the project folder.
#######################################################################################################################
##
## Preface: Changing the Windows PowerShell Script Execution Policy
##			The Set-ExecutionPolicy cmdlet enables you to determine which Windows PowerShell scripts 
##			will be allowed to run on your computer. Windows PowerShell has four different execution policies:
##			
##			Restricted - No scripts can be run. Windows PowerShell can be used only in interactive mode.
##
##			AllSigned - Only scripts signed by a trusted publisher can be run.
##
##			RemoteSigned - Downloaded scripts must be signed by a trusted publisher before they can be run.
##
##			Unrestricted - No restrictions; all Windows PowerShell scripts can be run.
##			
##
##			To Enable Set-ExecutionPolicy Cmdlet:
##			Go to Start Menu and search for "Windows PowerShell". 
##			Right click the x86 version and choose "Run as administrator".
##			Type "Set-ExecutionPolicy RemoteSigned"; run the script. Choose "Yes".
#######################################################################################################################			
##	
## Usage:   Start a PowerShell process and navigate to the directory which has this script.
##			Ex) cd c:\Sandbox\PS
##
##			Type ./assetcopy.ps1 to run the script.
##			
##			The parameters below will have to be modifed on a per project basis, or they can be read in from a file
##			in future releases.
##			
##			The directories must have a trailing \ in the string.
#######################################################################################################################			
##	
## Errors:  If a file is missing, i.e. a filename was read from a file and can't be located in the master asset folder,
##			a error box will pop up indicating an error was dedicated and a log file will be created in the directory
##			where the assets are copied to. This file will contain all of the missing files.
#######################################################################################################################

# Load assembly
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

##############################
# Parameters for the script
##############################

# Directory for the *.cpp / *.h files to be parsed for asset look-up
$srcDir = "C:\Sandbox\ui engine\UI_Engine\src\" # "C:\Sandbox\checkout\Source\BERET\"  "C:\Sandbox\ui engine\UI_Engine\src\"

# The master directory for assets
$masterDir = "C:\Sandbox\Assets\GUI\"

# Destination folder for which the project assets will be saved to
$dstDir = "C:\Sandbox\checkout\Source\BERET\UI_Data\GUI\"

# File extensions to look for
$extensionArray = @(".png", ".tga");

$errorFileName = "script_errors.log";

$listofSubDirectories = @();
$listofSubDirectories +=  Get-ChildItem $masterDir | where {$_.Attributes -eq 'Directory'} ;

# Look for error file, if it exists, delete it...

if (Test-Path $dstDir$errorFileName)
{
	Remove-Item $dstDir$errorFileName;
}

# Parse our files and retrieve lines that contain our extensions
$fileList = get-childitem $srcDir"*.cpp", $srcDir"*.h" | select-string -pattern $extensionArray -simplematch   |  foreach {$_.line}


$fileListArray = @();
$fileListArrayFiltered = @();
# Parse all the lines that we have, trimming them and some other voodoo magic.
for ($i=0; $i -lt $fileList.length; $i++)
{
	$fileList[$i] = $fileList[$i].trim();
	$fileList[$i] = $fileList[$i].ToLower();
	$begin = $fileList[$i].IndexOf('"');
	$endOfString = $fileList[$i].LastIndexOf(';');
	# This will deal with cases where we just have .extension, not an actual filename, such as for conditional checks...
	if ($endOfString  -eq -1)
	{
		continue;
	}	
	
	$fileList[$i] = $fileList[$i].Substring($begin+1, ($endOfString-2)-$begin);
	$fileListArray  += $fileList[$i].Split('"');
}

# Look for entries that contain our file extensions (right now we broken up lines that may or may not contain .extension filenames)
for ($i=0; $i -lt $fileListArray.length; $i++)
{
	for ($j=0; $j -lt $extensionArray.length; $j++)
	{
		if ($fileListArray[$i] -Match $extensionArray[$j])
		{		
			$fileListArrayFiltered += $fileListArray[$i];
		}	
	}
}
# Edge cases
for ($i=0; $i -lt $fileListArrayFiltered.length; $i++)
{
	# this will deal with % entries, such as  sprintf_s(..., ..., "%d....extension", ...);
	$delim = $fileListArrayFiltered[$i].LastIndexOf('%');
	if ($delim -ne -1)
	{
		$fileListArrayFiltered[$i] = $fileListArrayFiltered[$i].Substring(0, $delim);
	}
	# This will deal with nested files root\\directory\\file
	$delim = $fileListArrayFiltered[$i].LastIndexOf("\\");
	if ($delim -ne -1)
	{
		$fileListArrayFiltered[$i] = $fileListArrayFiltered[$i].Substring($delim + 2, ($fileListArrayFiltered[$i].length - 2) - $delim);
	}	
}
# Remove duplicates
$fileListArrayFiltered  = $fileListArrayFiltered  | sort -unique;


# Retrieve all files in both the master and project's asset folders, excluding directories.
$masterListofDirectories = @();
$masterListofDirectories += Get-ChildItem -Path $masterDir -Recurse -Force | Where-Object {$_ -isnot [IO.DirectoryInfo]};

$projectListofDirectories = @();
$projectListofDirectories += Get-ChildItem -Path $dstDir -Recurse -Force | Where-Object {$_ -isnot [IO.DirectoryInfo]};

$files = @();

# If files exist in the project directory, we compare the two and get unique elements firstly and also elements that have a newer write time (updated asset).
if ($projectListofDirectories)
{ 
	$files = (Compare-Object -referenceobject $masterListofDirectories -differenceobject $projectListofDirectories | ForEach {$_.InputObject});

	$listOfUpdatedFiles = @();

	for($i=0; $i -lt $masterListofDirectories.length; $i++)
	{

		for($j=0; $j -lt $projectListofDirectories.length; $j++)
		{
			if( ($masterListofDirectories[$i].LastWriteTime -gt $projectListofDirectories[$j].LastWriteTime) -and ($masterListofDirectories[$i].Name -eq $projectListofDirectories[$j].Name) )
			{
				$listOfUpdatedFiles += $masterListofDirectories[$i];
			}
		}
	}
	# Combine everything, the uniques and the newer versions of files 
	$files += $listOfUpdatedFiles;	
}
# Nothing is in the project directory, so we have the entire master asset folder to go through...
else
{
	$files = $masterListofDirectories; 
}

$missedFilesTempA = @();
$count = 0;

# Look through our list of files, making sure to check to see if any directories need to be created
# If a match is found, copy the item, if not, add that file to the missed files array.
for($i=0; $i -lt $fileListArrayFiltered.length; $i++)
{
	$fileFound = $FALSE;
	for($j=0; $j -lt $files.length; $j++)
	{
		$file = $files[$j].Name;
		if ($file -Match $fileListArrayFiltered[$i])
		{
			$fileFound = $TRUE;
			$subFolderFound = $FALSE;
			for ($k=0; $k -lt $listofSubDirectories.length; $k++)
			{
				if ($listofSubDirectories[$k].Name -eq $files[$j].Directory.Name)
				{
					if (!(Test-Path -Path ($dstDir + $listofSubDirectories[$k].Name) ))
					{
						New-Item -ItemType directory -Path ($dstDir +$listofSubDirectories[$k].Name)
					}
					Copy-Item $files[$j].FullName ($dstDir + $files[$j].Directory.Name);	
					$subFolderFound  = $TRUE;
					$count++;
				}		
			}
			if ($subFolderFound -eq $FALSE)
			{
				Copy-Item $files[$j].FullName ($dstDir);
				$count++;
			}
		}
	}
	
	if (!$fileFound)
	{
		$missedFilesTempA += $fileListArrayFiltered[$i]; 
	}
}
$missedFilesTempB = @();

# This will cross reference assets that are already in the directory, it is not a missed file if it already exists...
if ($projectListofDirectories)
{
	for($i=0; $i -lt $fileListArrayFiltered.length; $i++)
	{
		$fileFound = $FALSE;
		
		for($j=0; $j -lt $projectListofDirectories.length; $j++)
		{
			$fileTemp = $projectListofDirectories[$j].Name;
			if ($fileTemp -Match $fileListArrayFiltered[$i])
			{
				$fileFound = $TRUE;
			}
		}
		if ($fileFound -eq $FALSE)
		{
			$missedFilesTempB += $fileListArrayFiltered[$i]; 	
		}	
	}
	# Duplicate entries are legit files that we are missing, make sure to add them to our missed files array.
	foreach ($ea in $missedFilesTempA ) 
	{ 
		foreach ($eb in $missedFilesTempB)
		{
			if ($eb -eq $ea)
			{
				$missedFiles += $eb;
			}
		}
	}		
}
else
{
	$missedFiles = $missedFilesTempA
}
$result = "Copied " + $count + " files";
# If we missed any then report it as an error.
if ($missedFiles)
{
	# ERROR
	$logfile = $dstDir + $errorFileName;
	$warning = "Missing Files: " + $missedFiles + " `nReport created at " + $logfile;
	[System.Windows.Forms.MessageBox]::Show($warning,"ERROR",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error);
	Add-content $logfile -value $missedFiles;		
		
}
else
{
	# We did it!
	[System.Windows.Forms.MessageBox]::Show($result,"Success",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Asterisk)
}

