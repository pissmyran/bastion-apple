import XCTest
@testable import SSHCore

// Fixtur byggd på verklig utdata från en Ubuntu-maskin.
private let fixture = """
@@LOADAVG
2.53 1.86 1.81 3/1005 1015672
@@UPTIME
259335.25 2634310.61
@@MEM
MemTotal:       15244848 kB
MemFree:          680100 kB
MemAvailable:   10814800 kB
@@DF
Filesystem          1024-blocks       Used   Available Capacity Mounted on
tmpfs                   3048972       2472     3046500       1% /run
/dev/nvme0n1p2        102626232   22509936    74857032      24% /
tmpfs                   7622424          0     7622424       0% /dev/shm
@@OS
PRETTY_NAME="Ubuntu 26.04 LTS"
NAME="Ubuntu"
@@KERNEL
Linux 7.0.0-27-generic
@@HOST
mp100
@@NPROC
12
@@DOCKER
a1b2c3d4e5f6|plex|linuxserver/plex:latest|Up 3 days
f6e5d4c3b2a1|radarr|linuxserver/radarr|Up 2 hours (healthy)
@@END
"""

final class SystemProbeTests: XCTestCase {
    func testParsesFullSnapshot() {
        let s = SystemProbe.parse(fixture)

        XCTAssertEqual(s.load, LoadAverage(one: 2.53, five: 1.86, fifteen: 1.81))
        XCTAssertEqual(s.uptimeSeconds, 259335.25)
        XCTAssertEqual(s.kernel, "Linux 7.0.0-27-generic")
        XCTAssertEqual(s.hostname, "mp100")
        XCTAssertEqual(s.os, "Ubuntu 26.04 LTS")
        XCTAssertEqual(s.cpuCount, 12)

        XCTAssertEqual(s.memory?.totalBytes, 15244848 * 1024)
        XCTAssertEqual(s.memory?.availableBytes, 10814800 * 1024)
        XCTAssertEqual(s.memory?.usedBytes, (15244848 - 10814800) * 1024)

        // Rot-disken plockas ut korrekt bland flera monteringar.
        XCTAssertEqual(s.disks.count, 3)
        let root = s.rootDisk
        XCTAssertEqual(root?.filesystem, "/dev/nvme0n1p2")
        XCTAssertEqual(root?.capacityPercent, 24)
        XCTAssertEqual(root?.sizeBytes, 102626232 * 1024)

        XCTAssertEqual(s.containers.count, 2)
        XCTAssertEqual(s.containers.first?.name, "plex")
        XCTAssertEqual(s.containers.last?.status, "Up 2 hours (healthy)")
    }

    func testMissingSectionsAreNilNotCrash() {
        // Minimal maskin: ingen docker, ingen nproc, ingen os-release.
        let minimal = """
        @@LOADAVG
        0.00 0.01 0.05 1/100 999
        @@MEM
        MemTotal:       1000000 kB
        MemAvailable:    500000 kB
        @@DF
        @@DOCKER
        @@END
        """
        let s = SystemProbe.parse(minimal)
        XCTAssertEqual(s.load?.one, 0.0)
        XCTAssertEqual(s.memory?.usedFraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertNil(s.cpuCount)
        XCTAssertNil(s.os)
        XCTAssertNil(s.rootDisk)
        XCTAssertTrue(s.containers.isEmpty)
    }

    func testGarbageOutputYieldsEmptySnapshot() {
        let s = SystemProbe.parse("slumpmässigt skräp utan markörer")
        XCTAssertNil(s.load)
        XCTAssertNil(s.memory)
        XCTAssertTrue(s.disks.isEmpty)
    }

    func testMemoryRejectsInvalidCountersWithoutLosingOtherMetrics() {
        let largestKB = Int64.max / 1024
        for (total, available) in [
            ("-1", "0"), ("1", "-1"), ("1", "2"),
            (String(largestKB + 1), "0"), (String(largestKB + 1), String(largestKB + 1)),
            (String(Int64.min), "0")
        ] {
            let s = SystemProbe.parse("@@MEM\nMemTotal: \(total) kB\nMemAvailable: \(available) kB\n@@HOST\nhost\n")
            XCTAssertNil(s.memory, "total=\(total) available=\(available)")
            XCTAssertEqual(s.hostname, "host")
        }
        let s = SystemProbe.parse("@@MEM\nMemTotal: \(largestKB) kB\nMemAvailable: 0 kB\n")
        XCTAssertEqual(s.memory?.usedBytes, largestKB * 1024)
    }

    func testMemoryUsedBytesHandlesMutatedOrDecodedExtremes() {
        XCTAssertEqual(MemoryInfo(totalBytes: .max, availableBytes: .min).usedBytes, .max)
        XCTAssertEqual(MemoryInfo(totalBytes: .min, availableBytes: .max).usedBytes, 0)
        XCTAssertEqual(MemoryInfo(totalBytes: 10, availableBytes: 20).usedBytes, 0)
    }

    func testDisksSkipOverflowNegativeValuesAndUsedAboveSize() {
        let largestKB = Int64.max / 1024
        let smallestKB = Int64.min / 1024
        let s = SystemProbe.parse("""
        @@DF
        /ok \(largestKB) \(largestKB) 0 100% /ok
        /size \(largestKB + 1) 0 0 0% /size
        /used 1 \(largestKB + 1) 0 0% /used
        /avail 1 0 \(smallestKB - 1) 0% /avail
        /negative-size -1 0 0 0% /negative-size
        /negative-used 1 -1 0 0% /negative-used
        /negative-avail 1 0 -1 0% /negative-avail
        /used-above-size 1 2 0 200% /used-above-size
        /zero 0 0 0 0% /zero
        """)
        XCTAssertEqual(s.disks.map(\.mount), ["/ok", "/zero"])
        XCTAssertEqual(s.disks.first?.sizeBytes, largestKB * 1024)
        XCTAssertEqual(s.disks.first?.usedBytes, largestKB * 1024)
        XCTAssertEqual(s.disks.first?.availableBytes, 0)
    }

    func testUptimeRejectsValuesUnsafeForIntegerConversion() {
        for value in ["nan", "inf", "-inf", "-1", "1e100", String(Double(Int.max).nextUp)] {
            XCTAssertNil(SystemProbe.parse("@@UPTIME\n\(value) 0\n").uptimeSeconds, value)
        }
        for value in [0.0, 1.25, Double(Int.max).nextDown] {
            XCTAssertEqual(SystemProbe.parse("@@UPTIME\n\(value) 0\n").uptimeSeconds, value)
        }
    }
}
