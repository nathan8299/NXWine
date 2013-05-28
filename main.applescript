-- 
-- NXWine.app - No X11 Wine for OS X
-- 
-- Copyright (C) 2013 mattintosh4 <mattintosh4@gmx.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 

property wine : missing value
property wineserver : missing value

on NXWineGetPath_()
    set prefix to quoted form of POSIX path of (path to resource "bin")
    set wine to prefix & "wine" & space
    set wineserver to prefix & "wineserver -p0;"
end NXWineGetPath_

on main(input)
    NXWineGetPath_()
    try
        do shell script wineserver & wine & input
    end try
end main

on open argv
    repeat with aFile in argv
        main("start /Unix" & space & quoted form of (POSIX path of aFile))
    end repeat
end open

on run
    main("explorer")
end run