# frozen_string_literal: true

module MangaDownloader
  # Wraps the platform-specific `malloc_trim` call used to return freed pages
  # to the OS during long download runs. Isolated here so the downloader stays
  # about downloading.
  module Memory
    module_function

    def release
      GC.start(full_mark: true, immediate_sweep: true)
      trim_malloc
    rescue StandardError
      nil
    end

    def trim_malloc
      return unless RUBY_PLATFORM.include?('linux')

      @trim_malloc ||= begin
        require 'fiddle'
        Fiddle::Function.new(
          Fiddle.dlopen(nil)['malloc_trim'],
          [Fiddle::TYPE_LONG],
          Fiddle::TYPE_INT
        )
      rescue StandardError, LoadError
        # fiddle may be unavailable (e.g. Ruby 4 without the gem); memory
        # trimming is an optimisation, so degrade to plain GC.
        nil
      end

      @trim_malloc&.call(0)
    end
  end
end
