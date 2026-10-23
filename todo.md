## fixes
1. decide if option 'a' and 'c' should be only one and then make the unique option be 
the 'c' and allow to choose to download all manga or just specific chapters using a 
switch case accordgly input(all or 1-50 por example)
2. option e should not exist, only need option b to add and d to show list, 
so download from list should come from the option d after showing the list(Download one now? enter the letter. 
Then after selecting one ask is download specific chapters or all manga. if already 
downloaded some chapters option all chapters will not be suggested)

- make the download of chapters of already partially downloaded manga go to the already 
existing folder instead of creating another folder changing uppercase for lowercase

- discover why maybe meant to be chapter 1 doesn't download
- discover why maybe meant to be chapter 1 vagabond doesn't download

- option C don't need to exist if option A allows to download specific chapters
with a list of options [A] download all manga\n [B] download a interval of chapters
- make the [A] option download from first chapter to the last, as the option [C]
already does.

- seems like option c searches locally for jsons. Option a must do the same.

- check if memory usage is increasing after each chapter download. If yes, correct it.
- make the program save in a file the chapters not downloaded, this way we check for errors.
- investigate why ram consuption increases after each chapter downloaded
- make the manga be downloaded inside the a "manga" folder to not be scattered in root
- improve the stealth of headless browser checking akita article and if possible what he used for yahoo scraping he did
- only treat as downloaded in list (option [d]) if the manga is complete, 
to check this can compare the amount of chapters listed on json and the amount of chapters 
inside the folder of manga, after the check knowing it was already downloaded this state must be 
saved and not check again based on existing of manga folder, but about the state saved, 
like a [downloaded] aside the manga name. The reason for this is that I zip and pass to hdd much times.
- Bakuman in list of mangas appears with a symbol after the name and makes difficult to select it.
make the names of list be in lowercase or at least make the search find it by proximity of name, turning the name of manga 
from list lowercase in memory and matching the majority of letters in the order
- allow the program to set cronjobs to when running in server be able to start download 
from times to times

## Features to implement:
- treat the case if the user enter to download the latest chapter of hunter x hunter and it isn't on the already 
existing hunter x hunter.json file, then scrape the hunter hunter page to see if there is the chapter the user wants
if there is one, download it.
like https://atsu.moe/manga/MSUd3 or manga/MSUd3
- show amount of chapters in the side of manga name
- implement a way to use 2 or 3 ips to download faster. like using oracle vms or 
some similar cloud services
- option "miscellaneous" that will have info like worse time possible
of download and estimate time. Can do this with the sum of some manga downloads 
waiting time
- show total download time after finishing downloading a manga
- make chromium headless be launched in parallel with menu (will have to add exceptions or check-ins to work properly)
- remove the message: "Saved 327 chapters to /home/newm/projects/mangaDownloader/jsons/Vagabond.json"
- add a way to manage the mangas that have more than one source(maybe meant to be is one of those)
- allow to continue from where stopped downloading.
- reverse the order of downloads, has to start from first chapter, not the last one.
- Treat the cases where there is more than a source. Must ask to choose one or making 
one of them default with fallback to other sources. treat the case if the source 
from where we download stop being one to fallback to other(e.g: if webtoons is the source 
but only goes until chapter 50 and 51+ is from alpha, then must download from alpha from there)
- check the todo-and-explanations.md to other implementations and merge on this file.
- make the scraping download novels too.
- differentiate novels from manga/manwha and download accordingly
- make possible to configure the path the manga will be put while downloading it.
- create a option to program allow zip the root folder with manga name 
- add colors to messages displayed in downloads. Refer to print 
- show number of chapters when using option [C] to search a manga.
- all sublists should be in a different color from the common lists
u
- allow users to pass a list of manga names to download
- before searching for a manga in the website, must check first if there is a 
*.json for the manga name provided
- allow to download placing the url of manga directly, 
<<<<<<< HEAD

## DONE
- decrease the maximum time of waiting in downloading a chapter to 70s [DONE]
- create a rake function to delete the jsons of mangas already fully downloaded
