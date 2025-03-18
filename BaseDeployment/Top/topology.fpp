module BaseDeployment {

  # ----------------------------------------------------------------------
  # Symbolic constants for port numbers
  # ----------------------------------------------------------------------

    enum Ports_RateGroups {
      rateGroup1Khz_ID
      rateGroup10Khz_ID
    }

    enum Ports_StaticMemory {
      framer
      deframer
      deframing
    }

  topology BaseDeployment {

    # ----------------------------------------------------------------------
    # Instances used in the topology
    # ----------------------------------------------------------------------

    instance cmdDisp
    instance commDriver
    instance deframer
    instance eventLogger
    instance fatalAdapter
    instance fatalHandler
    instance framer
    instance gpioDriver
    instance led
    instance rateDriver
    instance rateGroup1Khz
    instance rateGroup10Khz
    instance rateGroupDriver
    instance systemResources
    instance textLogger
    instance timeHandler
    instance bufferManager
    instance tlmSend

    # ----------------------------------------------------------------------
    # Pattern graph specifiers
    # ----------------------------------------------------------------------

    command connections instance cmdDisp

    event connections instance eventLogger

    telemetry connections instance tlmSend

    text event connections instance textLogger

    time connections instance timeHandler

    # ----------------------------------------------------------------------
    # Direct graph specifiers
    # ----------------------------------------------------------------------

    connections RateGroups {
      # Block driver
      rateDriver.CycleOut -> rateGroupDriver.CycleIn

      # Rate group 1
      rateGroupDriver.CycleOut[Ports_RateGroups.rateGroup1Khz_ID] -> rateGroup1Khz.CycleIn
      rateGroup1Khz.RateGroupMemberOut[0] -> systemResources.run
      rateGroup1Khz.RateGroupMemberOut[1] -> tlmSend.Run
      rateGroup1Khz.RateGroupMemberOut[2] -> led.run

      rateGroupDriver.CycleOut[Ports_RateGroups.rateGroup10Khz_ID] -> rateGroup10Khz.CycleIn
      rateGroup10Khz.RateGroupMemberOut[0] -> commDriver.schedIn
      rateGroup10Khz.RateGroupMemberOut[1] -> bufferManager.schedIn
    }

    connections LedConnections {
      # led's gpioSet output is connected to gpioDriver's gpioWrite input
      led.gpioSet -> gpioDriver.gpioWrite
    }

    connections FaultProtection {
      eventLogger.FatalAnnounce -> fatalHandler.FatalReceive
    }

    connections SerialComms {
      # Downlink
      tlmSend.PktSend -> framer.comIn
      eventLogger.PktSend -> framer.comIn

      framer.framedAllocate -> bufferManager.bufferGetCallee
      framer.framedOut -> commDriver.$send

      commDriver.deallocate -> bufferManager.bufferSendIn


      # Uplink
      commDriver.$recv -> deframer.framedIn
      commDriver.allocate -> bufferManager.bufferGetCallee

      deframer.framedDeallocate -> bufferManager.bufferSendIn

      deframer.comOut -> cmdDisp.seqCmdBuff
      cmdDisp.seqCmdStatus -> deframer.cmdResponseIn

      deframer.bufferAllocate -> bufferManager.bufferGetCallee
      deframer.bufferDeallocate -> bufferManager.bufferSendIn
    }

  }

}
