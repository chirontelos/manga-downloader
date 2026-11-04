# frozen_string_literal: true

module MangaDownloader
  module UI
    # The only object allowed to read stdin. Swappable in tests and in
    # non-interactive contexts.
    class Console
      def initialize(input: $stdin, output: $stdout)
        @input = input
        @output = output
      end

      # Returns a chomped line, or nil at end-of-input.
      def ask(prompt)
        @output.print(prompt)
        @output.flush
        line = @input.gets
        line&.chomp
      end
    end
  end
end
