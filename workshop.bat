@echo off
setlocal
set workshopid=2943025031
set workshopurl=https://steamcommunity.com/sharedfiles/filedetails/changelog/

:pack
if exist temp.gma (
	echo Deleting temp.gma to make room for new GMA file
	del temp.gma
)

echo Packing an addon file
gmad.exe create -folder ./ -out ./temp.gma

echo Continuing will publish the addon, close me if you don't want that
echo.

:prompt
echo What do we do with the workshop? The current workshop id is %workshopid%
echo id         : Lists all workshop addons and prompts for a workshop ID
echo publish    : Create a new workshop page
echo skip       : Skip the gmpublish process entirely
echo update     : Update the GMA on the workshop
echo updateicon : Update the GMA and icon file on the workshop (icon must be a 512x512 jpg)
echo.
set /P choice=Choose: 

rem is there a better way to do this? I wouldn't know I don't make batch files!
if /i "%choice%" EQU "id" goto id end
if /i "%choice%" EQU "publish" goto publish end
if /i "%choice%" EQU "update" goto update end
if /i "%choice%" EQU "updateicon" goto updateicon end

rem abbreviations
if /i "%choice%" EQU "p" goto publish end
if /i "%choice%" EQU "q" goto skip end
if /i "%choice%" EQU "s" goto skip end
if /i "%choice%" EQU "u" goto update end

echo.
echo Invalid choice
echo.
goto prompt

:id
gmpublish.exe list
echo.
set /P workshopid=ID: 
goto prompt

:publish
echo Publishing workshop addon...
gmpublish.exe create -icon ./icon.jpg -addon ./temp.gma
set workshopurl=https://steamcommunity.com/sharedfiles/filedetails/?id=
gmpublish.exe list
echo.
set /P workshopid=ID: 
goto skip

:update
echo Updating GMA on workshop
gmpublish.exe update -id %workshopid% -addon ./temp.gma -changes "Pending edit..."
goto skip

:updateicon
echo Updating GMA and icon on workshop
gmpublish.exe update -id %workshopid% -addon ./temp.gma -changes "Pending edit..."
goto skip

:skip

echo Removing the temporary GMA file
del temp.gma
echo Now go edit the change note
start "" %workshopurl%%workshopid%
echo.

endlocal
pause