require "vagrant"

module VagrantPlugins
  module GuestSmartOS
    class Guest < Vagrant.plugin("2", :guest)
      def detect?(machine)
        machine.communicate.test("cat /etc/release | grep -i SmartOS")
      end
    end
  end
end
