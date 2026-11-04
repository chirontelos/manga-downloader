# frozen_string_literal: true

module MangaDownloader
  # Letters used to let the user select from a list: a..z first, then ab..az,
  # ba..bz, ... when there are more than 26 entries.
  module Labels
    module_function

    def for(count)
      letters = ('a'..'z').to_a
      labels = letters.dup

      letters.each do |first|
        letters.each do |second|
          next if first == 'a' && second == 'a'

          labels << "#{first}#{second}"
        end
      end

      labels.first(count)
    end
  end
end
