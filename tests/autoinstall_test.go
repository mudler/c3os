package mos_test

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	. "github.com/spectrocloud/peg/matcher"
)

var _ = Describe("kairos autoinstall test", Label("autoinstall-test"), func() {

	stateAssert := func(query, expected string) {
		out, err := Sudo(fmt.Sprintf("kairos-agent state get .%s", query))
		ExpectWithOffset(1, err).ToNot(HaveOccurred())
		ExpectWithOffset(1, out).To(ContainSubstring(expected))
	}

	BeforeEach(func() {
		if os.Getenv("CLOUD_INIT") == "" || !filepath.IsAbs(os.Getenv("CLOUD_INIT")) {
			Fail("CLOUD_INIT must be set and must be pointing to a file as an absolute path")
		}

		EventuallyConnects(1200)
	})

	AfterEach(func() {
		if CurrentGinkgoTestDescription().Failed {
			gatherLogs()
		}
	})

	Context("live cd", func() {
		It("has default service active", func() {
			if os.Getenv("FLAVOR") == "alpine" {
				out, _ := Sudo("rc-status")
				Expect(out).Should(ContainSubstring("kairos"))
				Expect(out).Should(ContainSubstring("kairos-agent"))
				fmt.Println(out)
			} else {
				// Eventually(func() string {
				// 	out, _ := machine.Command("sudo systemctl status kairososososos-agent")
				// 	return out
				// }, 30*time.Second, 10*time.Second).Should(ContainSubstring("no network token"))

				out, _ := Machine.Command("sudo systemctl status kairos")
				Expect(out).Should(ContainSubstring("loaded (/etc/systemd/system/kairos.service; enabled;"))
				fmt.Println(out)
			}

			// Debug output
			out, _ := Sudo("ls -liah /oem")
			fmt.Println(out)
			//	Expect(out).To(ContainSubstring("userdata.yaml"))
			out, _ = Sudo("cat /oem/userdata")
			fmt.Println(out)
			out, _ = Sudo("sudo ps aux")
			fmt.Println(out)

			out, _ = Sudo("sudo lsblk")
			fmt.Println(out)

		})

		It("passes basic state checks", func() {
			stateAssert("oem.mounted", "false")
			stateAssert("persistent.mounted", "false")
			stateAssert("state.mounted", "false")
		})
	})

	Context("auto installs", func() {
		It("to disk with custom config", func() {
			Eventually(func() string {
				out, _ := Sudo("ps aux")
				return out
			}, 30*time.Minute, 1*time.Second).Should(
				Or(
					ContainSubstring("elemental install"),
				))
		})
	})

	Context("reboots and passes functional tests", func() {
		It("has grubenv file", func() {
			Eventually(func() string {
				out, _ := Sudo("sudo cat /oem/grubenv")
				return out
			}, 40*time.Minute, 1*time.Second).Should(
				Or(
					ContainSubstring("foobarzz"),
				))
		})

		It("has custom cmdline", func() {
			Eventually(func() string {
				out, _ := Sudo("sudo cat /proc/cmdline")
				return out
			}, 30*time.Minute, 1*time.Second).Should(
				Or(
					ContainSubstring("foobarzz"),
				))
		})

		It("uses the dracut immutable module", func() {
			out, err := Sudo("cat /proc/cmdline")
			Expect(err).ToNot(HaveOccurred())
			Expect(out).To(ContainSubstring("cos-img/filename="))
		})

		It("installs Auto assessment", func() {
			// Auto assessment was installed
			out, _ := Sudo("cat /run/initramfs/cos-state/grubcustom")
			Expect(out).To(ContainSubstring("bootfile_loc"))

			out, _ = Sudo("cat /run/initramfs/cos-state/grub_boot_assessment")
			Expect(out).To(ContainSubstring("boot_assessment_blk"))

			cmdline, _ := Sudo("cat /proc/cmdline")
			Expect(cmdline).To(ContainSubstring("rd.emergency=reboot rd.shell=0 panic=5"))
		})

		It("has writeable tmp", func() {
			_, err := Sudo("echo 'foo' > /tmp/bar")
			Expect(err).ToNot(HaveOccurred())

			out, err := Machine.Command("sudo cat /tmp/bar")
			Expect(err).ToNot(HaveOccurred())

			Expect(out).To(ContainSubstring("foo"))
		})

		It("has corresponding state", func() {
			out, err := Sudo("kairos-agent state")
			Expect(err).ToNot(HaveOccurred())
			fmt.Println(out)
			Expect(out).To(ContainSubstring("boot: active_boot"))

			stateAssert("oem.mounted", "true")
			stateAssert("persistent.mounted", "true")
			stateAssert("state.mounted", "true")
			stateAssert("oem.type", "ext4")
			stateAssert("persistent.type", "ext4")
			stateAssert("state.type", "ext4")
			stateAssert("oem.mount_point", "/oem")
			stateAssert("persistent.mount_point", "/usr/local")
			stateAssert("state.mount_point", "/run/initramfs/cos-state")
			stateAssert("oem.read_only", "false")
			stateAssert("persistent.read_only", "false")
			stateAssert("state.read_only", "true")
		})
	})
})
