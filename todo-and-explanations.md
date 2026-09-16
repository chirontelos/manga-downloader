 # server version
    # allow the manga to be stored in zip and if some user asks for an already downloaded manga
    # block the loading of images and the like to avoid bandwidth waste https://railsnotes.xyz/
    #
    # v2
    # main.rb should be atsu_scraper.rb
    # download.rb must remain being a separate file.
    # the ideal is to name of manga be stored in file and download.rb will pull from there to name the directory and call the *.json to store the images. 
    # maybe download.rb can be called with args on command line with the name of manga and the main.rb will call the download.rb this way to download specific mangas
    # menu must collect the name of manga and pass it to the methods of main.rb and append to file too.
    # check if will have to save composed names with underscore or can be space as the program already does.
    # read: https://akitaonrails.com/en/2017/06/13/ex-manga-downloadr-part-6-the-rise-of-flow/

    # allow user to pass a list of manga names and download it
    # make browser seems more like a normal browser (https://railsnotes.xyz/blog/ferrum-stealth
    # use cellphones as proxy or maybe use 2 oracle servers
    # maybe using catimg to display images, but first check how windows terminal have or if doc
    #create a method to correct name and put in the correct place the first chapter of each manga in [manga].json

    # ask name input from user
    # make browser seems more real by using options
    # search the name input and return the result
    # case 404 or similar warn about it
    # if request sucessfull returns the names of mangas and authors
    # user selects what he wants by the names returned
    # after the selection the program will access the chapters pages, then each chapter page us
    # one dir will be created with the name of manga and inside it the other folders will be cr
    # all the .webp images will be downloaded using concurrency, but one chapter at each 6 seco
    # print on screen the loading of downloads updating the same line instead of printing new l
    # see the usage of this: page.network.wait_for_idle(rand(5..14))
   # FIX: take the first values on .json and put as last, this way the order will be correct

   # NOTE: explanations

    # An idle network method ensures a webpage has finished loading its background data
    # before your automation script moves to the next step.
    # In browser automation libraries like Ferrum (used in Ruby), wait_for_idle pauses
    # execution until the network stops sending and receiving data, preventing scripts from
    # failing because elements haven't loaded yet.
    #
    # wait_for_idle returns true if the network goes quiet, or false if it times out.
    # wait_for_idle! does the same but crashes your script with an error (Ferrum::TimeoutError)
    #
    # Modern websites use JavaScript to load content asynchronously after the main page
    # structure is already there. If your script clicks a button and immediately tries to scrap
    # the next page, it will likely fail because the data hasn't arrived yet. This method force
    # script to wait until the network traffic settles.

### menu
  # NOTE: menu
    # puts 'Manga Downloader'.colorize(:green)
    # puts
    #
    # input = ''
    #
    # # uncomment here
    # until input == 'exit'
    #   # maybe use heredoc here
    #   puts '[a] manga name to download:'
    #   puts '[b] download from chapter x onwards:'
    #   puts '[c] list mangas' # divided by downloaded and on waiting
    #   puts '[d] download chapter'
    #   puts '[e] download from chapter x onwards'
    #   puts '[f] add manga to list'
    #   puts '[i] check new chapters'
    #
    #   input = gets.chomp
    # end
   # NOTE: menu
