# frozen_string_literal: true

module Census
  module AtHome
    # How much room a directory's filesystem has left. Ruby has no statvfs,
    # so this asks df, which Linux and macOS both have with -P (POSIX output)
    # and -k (kilobyte blocks).
    module Disk
      def self.free_bytes(path)
        line = `df -Pk #{path}`.lines.last.to_s.split
        return nil if line.size < 4

        Integer(line[3]) * 1024
      end
    end
  end
end
