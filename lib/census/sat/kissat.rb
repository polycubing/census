# frozen_string_literal: true

require "open3"
require "tempfile"

module Census
  module SAT
    # Runs the kissat solver on an Instance. Returns the set of true variables
    # for a satisfiable instance, nil for an unsatisfiable one.
    class Kissat
      SATISFIABLE = 10
      UNSATISFIABLE = 20

      # kissat exits zero when a limit stopped it before it decided anything.
      # That is a third answer, not a failure, and it is what makes a cube
      # splittable: nobody could finish this, so cut it in half.
      UNDECIDED = 0

      # instance_path keeps the generated CNF on disk — a DRAT proof is only
      # checkable against the exact formula it refutes.
      #
      # CENSUS_FFI=1 routes plain solves through the in-process IPASIR engine
      # (no spawn tax). Proof-capture and progress-streaming runs always use
      # the subprocess path — proofs and live statistics need it.
      def self.solve(instance, instance_path: nil, proof_path: nil, progress: nil)
        if ENV["CENSUS_FFI"] == "1" && proof_path.nil? && progress.nil?
          require_relative "ipasir"
          return IPASIR.solve(instance)
        end
        if instance_path
          File.open(instance_path, "w") { instance.write_dimacs(it) }
          return run(instance_path, proof_path:, progress:)
        end

        Tempfile.create(["census", ".cnf"]) do |file|
          instance.write_dimacs(file)
          file.flush
          run(file.path, proof_path:, progress:)
        end
      end

      # Solve a stored formula under a cube (a partial assignment appended as
      # unit clauses). Returns true variables for SAT, nil for UNSAT — the
      # distributed workers' entry point for cube units.
      #
      # With proof_path, the augmented formula is written to disk first, because
      # kissat only emits a DRAT proof for a formula handed to it as a file. The
      # formula is not kept: it is reproducible from cnf_path and the cube, so a
      # checker can rebuild the exact thing the proof refutes without it being
      # shipped anywhere.
      # With a timeout, an unfinished cube comes back :undecided rather than
      # running forever on a volunteer's laptop.
      # With max_proof_bytes, a proof that grows past it stops the solver and
      # the cube comes back :undecided too: a cube whose proof will not fit
      # is a cube to split, and a disk is not the place to find that out.
      #
      # The augmented formula goes to kissat through a named pipe rather than
      # a file. kissat reads it once, and six clients each writing a 3.9 GB
      # copy of the staircase's corona-3 formula was a third of the colo's
      # free disk.
      def self.solve_cube(cnf_path:, cube:, proof_path: nil, timeout: nil, max_proof_bytes: nil)
        return streamed_cube(cnf_path:, cube:) unless proof_path

        Dir.mktmpdir("census-cube") do |dir|
          fifo = File.join(dir, "formula.cnf")
          File.mkfifo(fifo)
          writer = Thread.new do
            File.open(fifo, "w") { |io| CubeFile.stream_augmented(cnf_path:, cube:, io:) }
          rescue Errno::EPIPE
            nil
          end
          begin
            run(fifo, proof_path:, timeout:, max_proof_bytes:)
          ensure
            writer.kill unless writer.join(5)
          end
        end
      end

      def self.streamed_cube(cnf_path:, cube:)
        output = IO.popen([ENV.fetch("CENSUS_SOLVER", "kissat")], "r+") do |io|
          CubeFile.stream_augmented(cnf_path:, cube:, io:)
          io.close_write
          io.read
        end
        case output[/^s (\w+)/, 1]
        when "SATISFIABLE" then true_variables(output)
        when "UNSATISFIABLE" then nil
        else raise "solver returned neither SAT nor UNSAT for #{cnf_path}"
        end
      end

      # With a progress IO, kissat runs un-quieted and its periodic statistics
      # lines stream there live; the verdict lines are parsed as usual.
      def self.run(path, proof_path: nil, progress: nil, timeout: nil, max_proof_bytes: nil)
        command = [ENV.fetch("CENSUS_SOLVER", "kissat")]
        command << "--quiet" unless progress
        command << "--time=#{timeout}" if timeout
        command << path
        command << proof_path if proof_path
        return streamed(command, progress) if progress
        return capped(command, proof_path, max_proof_bytes) if proof_path && max_proof_bytes

        output, status = Open3.capture2(*command)
        verdict(status.exitstatus, output)
      end

      # Run with a watcher on the proof file: past the cap, kissat is stopped
      # and the answer is :undecided, the same as a time limit.
      def self.capped(command, proof_path, max_proof_bytes)
        over = false
        output = nil
        status = nil
        Open3.popen2(*command) do |_stdin, stdout, waiter|
          watcher = Thread.new do
            until waiter.join(2)
              next unless File.exist?(proof_path) && File.size(proof_path) > max_proof_bytes

              over = true
              Process.kill("TERM", waiter.pid)
              break
            end
          end
          output = stdout.read
          status = waiter.value
          watcher.join
        end
        return :undecided if over

        verdict(status.exitstatus, output)
      end

      def self.streamed(command, progress)
        verdict_lines = []
        status = nil
        Open3.popen2(*command) do |_stdin, stdout, waiter|
          stdout.each_line do |line|
            if line.start_with?("c")
              progress.puts(line)
            else
              verdict_lines << line
            end
          end
          status = waiter.value
        end
        verdict(status.exitstatus, verdict_lines.join)
      end

      def self.verdict(exitstatus, output)
        case exitstatus
        when SATISFIABLE   then true_variables(output)
        when UNDECIDED     then :undecided
        when UNSATISFIABLE then nil
        else raise "kissat failed with exit status #{exitstatus}"
        end
      end

      def self.true_variables(output)
        output.lines
              .select { it.start_with?("v ") }
              .flat_map { it.split.drop(1) }
              .map { Integer(it) }
              .select(&:positive?)
              .to_set
      end
    end
  end
end
