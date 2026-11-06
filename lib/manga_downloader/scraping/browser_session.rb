# frozen_string_literal: true

require 'ferrum'

module MangaDownloader
  module Scraping
    # Owns the Chromium process so the CLI and the downloader launch it with
    # the same options.
    module BrowserSession
      module_function

      def open(config)
        browser = build(config)
        page = browser.create_page
        yield page
      ensure
        quit(browser)
      end

      def build(config)
        options = {
          headless: config.headless,
          timeout: config.page_timeout,
          protocol_timeout: config.protocol_timeout
        }
        options[:browser_path] = config.browser_path if config.browser_path
        Ferrum::Browser.new(**options)
      end

      def quit(browser)
        browser&.quit
      rescue StandardError
        nil
      end
    end
  end
end
