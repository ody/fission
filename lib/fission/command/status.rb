module Fission
  class Command
    class Status < Command

      def initialize(args=[])
        super
      end

      def execute
        all_vms = VM.all
        all_running_vms = VM.all_running

        longest_vm_name = all_vms.max { |a,b| a.length <=> b.length }

        VM.all.each do |vmname|
          vm=VM.new(vmname)
          status = vm.state
          Fission.ui.output_printf "%-#{longest_vm_name.length}s   %s\n", vmname, "["+status+"]"
        end
      end

      def option_parser
        optparse = OptionParser.new do |opts|
          opts.banner = "\nstatus usage: fission status"
        end

        optparse
      end

    end
  end
end
