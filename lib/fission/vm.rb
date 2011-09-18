module Fission
  class VM
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def create_snapshot(name)
      command = "#{Fission.config.attributes['vmrun_cmd']} snapshot #{conf_file.gsub ' ', '\ '} \"#{name}\" 2>&1"
      output = `#{command}`

      if $?.exitstatus == 0
        Fission.ui.output "Snapshot '#{name}' created"
      else
        Fission.ui.output "There was an error creating the snapshot."
        Fission.ui.output_and_exit "The error was:\n#{output}", 1
      end
    end

    def revert_to_snapshot(name)
      command = "#{Fission.config.attributes['vmrun_cmd']} revertToSnapshot #{conf_file.gsub ' ', '\ '} \"#{name}\" 2>&1"
      output = `#{command}`

      if $?.exitstatus == 0
        Fission.ui.output "Reverted to snapshot '#{name}'"
      else
        Fission.ui.output "There was an error reverting to the snapshot."
        Fission.ui.output_and_exit "The error was:\n#{output}", 1
      end
    end

    def snapshots
      command = "#{Fission.config.attributes['vmrun_cmd']} listSnapshots #{conf_file.gsub ' ', '\ '} 2>&1"
      output = `#{command}`

      if $?.exitstatus == 0
        snaps = output.split("\n").select { |s| !s.include? 'Total snapshots:' }
        snaps.map { |s| s.strip }
      else
        Fission.ui.output "There was an error getting the list of snapshots."
        Fission.ui.output_and_exit "The error was:\n#{output}", 1
      end
    end

    def start(args={})
      command = "#{Fission.config.attributes['vmrun_cmd']} start #{conf_file.gsub ' ', '\ '} "

      if !args[:headless].blank? && args[:headless]
        command << "nogui 2>&1"
      else
        command << "gui 2>&1"
      end

      output = `#{command}`

      if $?.exitstatus == 0
        Fission.ui.output "VM started"
      else
        Fission.ui.output "There was a problem starting the VM.  The error was:\n#{output}"
      end
    end

    def stop
      command = "#{Fission.config.attributes['vmrun_cmd']} stop #{conf_file.gsub ' ', '\ '} 2>&1"
      output = `#{command}`

      if $?.exitstatus == 0
        Fission.ui.output "VM stopped"
      else
        Fission.ui.output "There was a problem stopping the VM.  The error was:\n#{output}"
      end
    end

    def halt
      command = "#{Fission.config.attributes['vmrun_cmd']} stop #{conf_file.gsub ' ', '\ '} hard 2>&1"
      output = `#{command}`

      if $?.exitstatus == 0
        Fission.ui.output "VM halted"
      else
        Fission.ui.output "There was a problem halting the VM.  The error was:\n#{output}"
      end
    end

    def suspend
      unless state!="running"
        command = "#{Fission.config.attributes['vmrun_cmd']} suspend #{conf_file.gsub ' ', '\ '} 2>&1"
        output = `#{command}`

        if $?.exitstatus == 0
          Fission.ui.output "VM suspended"
        else
          Fission.ui.output "There was a problem suspending the VM.  The error was:\n#{output}"
        end
      end
    end

    def resume
      if state=="suspended"
        start
      end
    end

    def state
      return "not created" unless exists?

      if VM.all_running.include?(name)
        return "running"
      else
        # It coud be suspended
        suspend_filename=File.join(File.dirname(conf_file), File.basename(conf_file,".vmx")+".vmem")
        if File.exists?(suspend_filename)
          return "suspended"
        else
          return "not running"
        end
      end
    end

    # Retrieve the first mac address for a vm
    # This will only retrieve the first auto generate mac address
    #
    # Usage :
    # > vm=Fission::VM.new("lucid64")
    # > vm.mac_address
    # => "00:0c:29:26:49:2c"
    def mac_address
      unless File.exists?(conf_file)
        return nil
      else
        line=File.new(conf_file).grep(/^ethernet0.generatedAddress =/)
        if line.nil?
          #Fission.ui.output "Hmm, the vmx file #{conf_file} does not contain a generated mac address "
        end
        address=line.first.split("=")[1].strip.split(/\"/)[1]
        return address
      end
    end

    # Retrieve the ip address for a vm.
    # This will only look for dynamically assigned ip address via vmware dhcp
    #
    # > vm=Fission::VM.new("lucid64")
    # > vm.ip_address
    #  => "172.16.44.139"
    #
    # Some pointers with extra info
    # - http://nileshk.com/2009/06/24/vmware-fusion-nat-dhcp-and-port-forwarding.html
    # - http://works13.com/blog/mac/ssh-your-arch-linux-vm-in-vmware-fusion.htm
    #
    #       /var/db/vmware/vmnet-dhcpd-vmnet8.leases
    #
    #       lease 172.16.44.134 {
    #         starts 4 2011/07/28 15:54:41;
    #         ends 4 2011/07/28 16:24:41;
    #         hardware ethernet 00:0c:29:54:06:5c;
    #       }
    #
    def ip_address

      if state!="running"
        return nil
      end
      # First we find the macaddress
      unless mac_address.nil?

        # Find all lines that contain a hardware element
        # and find the index of the last line that contains the mac address
        index=File.new("/var/db/vmware/vmnet-dhcpd-vmnet8.leases").grep(/hardware /).rindex{ |x| x.include?(mac_address)}

        if index.nil?
          # We could not find the mac address, so we give back a nil ip_addres
          return nil
        else
          lease_line=File.new("/var/db/vmware/vmnet-dhcpd-vmnet8.leases").grep(/^lease/)[index]
          unless lease_line.nil?
            ip=lease_line.split(/ /)[1]
            return ip
          else
            # Found no matching lease_line
            return nil
          end
        end

      else
        # No mac address was found for this machine so we can't calculate the ip-address
        return nil
      end
    end

    def conf_file
      vmx_path = File.join(self.class.path(@name), "*.vmx")
      conf_files = Dir.glob(vmx_path)

      case conf_files.count
      when 0
        Fission.ui.output_and_exit "Unable to find a config file for VM '#{@name}' (in '#{vmx_path}')", 1
      when 1
        conf_files.first
      else
        if conf_files.include?(File.join(File.dirname(vmx_path), "#{@name}.vmx"))
          File.join(File.dirname(vmx_path), "#{@name}.vmx")
        else
          output = "Multiple config files found for VM '#{@name}' ("
          output << conf_files.sort.map { |f| "'#{File.basename(f)}'" }.join(', ')
          output << " in '#{File.dirname(vmx_path)}')"
          Fission.ui.output_and_exit output, 1
        end
      end
    end

    def self.all
      vm_dirs = Dir[File.join Fission.config.attributes['vm_dir'], '*.vmwarevm'].select do |d|
        File.directory? d
      end

      vm_dirs.map { |d| File.basename d, '.vmwarevm' }
    end

    def self.all_running
      command = "#{Fission.config.attributes['vmrun_cmd']} list"

      output = `#{command}`

      if $?.exitstatus == 0
        vms = output.split("\n").select do |vm|
          vm.include?('.vmx') && File.exists?(vm) && File.extname(vm) == '.vmx'
        end

        vms.map { |vm| File.basename(File.dirname(vm), '.vmwarevm') }
      else
        Fission.ui.output_and_exit "Unable to determine the list of running VMs", 1
      end
    end

    def exists?
      Fission::VM.exists?(name)
    end

    def self.exists?(vm_name)
      File.directory? path(vm_name)
    end

    def self.path(vm_name)
      File.join Fission.config.attributes['vm_dir'], "#{vm_name}.vmwarevm"
    end

    def self.clone(source_vm, target_vm)
      Fission.ui.output "Cloning #{source_vm} to #{target_vm}"
      FileUtils.cp_r path(source_vm), path(target_vm)

      Fission.ui.output "Configuring #{target_vm}"
      rename_vm_files source_vm, target_vm
      update_config source_vm, target_vm

    end


    def self.delete(vm_name)
      Fission.ui.output "Deleting vm #{vm_name}"
      FileUtils.rm_rf path(vm_name)
      Fission::Metadata.delete_vm_info(path(vm_name))
    end


    private
    def self.rename_vm_files(from, to)
      files_to_rename(from, to).each do |file|
        text_to_replace = File.basename(file, File.extname(file))

        if File.extname(file) == '.vmdk'
          if file.match /\-s\d+\.vmdk/
            text_to_replace = file.partition(/\-s\d+.vmdk/).first
          end
        end

        unless File.exists?(File.join(path(to), file.gsub(text_to_replace, to)))
          FileUtils.mv File.join(path(to), file),
            File.join(path(to), file.gsub(text_to_replace, to))
        end
      end
    end

    def self.files_to_rename(from, to)
      files_which_match_source_vm = []
      other_files = []

      Dir.entries(path(to)).each do |f|
        unless f == '.' || f == '..'
          f.include?(from) ? files_which_match_source_vm << f : other_files << f
        end
      end

      files_which_match_source_vm + other_files
    end

    def self.vm_file_extensions
      ['.nvram', '.vmdk', '.vmem', '.vmsd', '.vmss', '.vmx', '.vmxf']
    end

    def self.update_config(from, to)
      ['.vmx', '.vmxf', '.vmdk'].each do |ext|
        file = File.join path(to), "#{to}#{ext}"

        unless File.binary?(file)
          text = (File.read file).gsub from, to
          File.open(file, 'w'){ |f| f.print text }
        end

      end

      # Rewrite vmx file to avoid messages
      new_vmx_file=File.open(File.join(path(to),"#{to}.vmx"),'r')

      content=new_vmx_file.read

      # Filter out other values
      content=content.gsub(/^tools.remindInstall.*\n/, "")
      content=content.gsub(/^uuid.action.*\n/,"").strip

      # Remove generate mac addresses
      content=content.gsub(/^ethernet.+generatedAddress.*\n/,"").strip

      # Add the correct values
      content=content+"\ntools.remindInstall = \"FALSE\"\n"
      content=content+"uuid.action = \"create\"\n"

      # Now rewrite the vmx file
      File.open(new_vmx_file,'w'){ |f| f.print content}

    end

  end
end
