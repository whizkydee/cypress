describe "$Cypress.Cy Clock Commands", ->
  enterCommandTestingMode()

  beforeEach ->
    @window = @cy.privateState("window")

    @setTimeoutSpy = @sandbox.spy(@window, "setTimeout")
    @setIntervalSpy = @sandbox.spy(@window, "setInterval")

  describe "#clock", ->
    it "sets clock as subject", ->
      @cy.clock().then (clock) ->
        expect(clock).to.exist
        expect(clock.tick).to.be.a("function")

    it "assigns clock to test context", ->
      @cy.clock().then (clock) ->
        expect(clock).to.equal(@clock)

    it "proxies lolex clock, replacing window time methods", (done) ->
      @cy.clock().then (clock) ->
        @window.setTimeout =>
          expect(@setTimeoutSpy).not.to.be.called
          done()
        clock.tick()

    it "takes now arg", ->
      now = 1111111111111
      @cy.clock(now).then (clock) ->
        expect(new @window.Date().getTime()).to.equal(now)
        clock.tick(4321)
        expect(new @window.Date().getTime()).to.equal(now + 4321)

    it "restores window time methods when calling restore", ->
      @cy.clock().then (clock) ->
        @window.setTimeout =>
          expect(@setTimeoutSpy).not.to.be.called
          clock.restore()
          expect(@window.setTimeout).to.equal(@setTimeoutSpy)
        clock.tick()

    it "unsets clock after restore", ->
      cy = @cy
      @cy.clock().then (clock) ->
        clock.restore()
        expect(cy._getClock()).to.be.null
        expect(@clock).to.be.null

    it "automatically restores clock on 'restore' event", ->
      clock = {restore: @sandbox.stub()}
      @cy._setClock(clock)
      @Cypress.trigger("restore")
      expect(clock.restore).to.be.called

    it "unsets clock before test run", ->
      @cy._setClock({})
      @Cypress.trigger("test:before:run", {})
      expect(@cy._getClock()).to.be.null

    it "returns clock on subsequent calls, ignoring arguments", ->
      @cy
        .clock()
        .clock(400)
        .then (clock) ->
          expect(clock._details().now).to.equal(0)

    context "errors", ->
      beforeEach ->
        @allowErrors()

      it "throws if now is not a number (or options object)", (done) ->
        @cy.on "fail", (err) ->
          expect(err.message).to.equal("cy.clock() only accepts a number or an options object for its first argument. You passed: \"250\"")
          done()

        @cy.clock("250")

      it "throws if methods is not an array (or options object)", (done) ->
        @cy.on "fail", (err) ->
          expect(err.message).to.equal("cy.clock() only accepts an array of function names or an options object for its second argument. You passed: \"setTimeout\"")
          done()

        @cy.clock(0, "setTimeout")

      it "throws if methods is not an array of strings (or options object)", (done) ->
        @cy.on "fail", (err) ->
          expect(err.message).to.equal("cy.clock() only accepts an array of function names or an options object for its second argument. You passed: [42]")
          done()

        @cy.clock(0, [42])

    context "arg for which functions to replace", ->
      it "replaces specified functions", (done) ->
        @cy.clock(null, ["setTimeout"]).then (clock) ->
          @window.setTimeout =>
            expect(@setTimeoutSpy).not.to.be.called
            done()
          clock.tick()

      it "does not replace other functions", (done) ->
        @cy.clock(null, ["setTimeout"]).then (clock) =>
          interval = @window.setInterval =>
            @window.clearInterval(interval)
            expect(@setIntervalSpy).to.be.called
            @window.setTimeout =>
              expect(@setTimeoutSpy).not.to.be.called
              done()
            clock.tick()
          , 5

    context "options", ->
      beforeEach ->
        @Cypress.on "log", (attrs, @log) =>

      it "can be first arg", ->
        @cy.clock({log: false}).then =>
          expect(@log).to.be.undefined

      it "can be second arg", ->
        @cy.clock(new Date().getTime(), {log: false}).then =>
          expect(@log).to.be.undefined

      it "can be third arg", ->
        @cy.clock(new Date().getTime(), ["setTimeout"], {log: false}).then =>
          expect(@log).to.be.undefined

    context "window changes", ->
      it "binds to default window before visit", ->
        @cy.clock(null, ["setTimeout"]).then (clock) =>
          onSetTimeout = @sandbox.spy()
          @cy.privateState("window").setTimeout(onSetTimeout)
          clock.tick()
          expect(onSetTimeout).to.be.called

      it "re-binds to new window when window changes", ->
        newWindow = {
          setTimeout: ->
          XMLHttpRequest: {
            prototype: {}
          }
        }
        @cy.clock(null, ["setTimeout"]).then (clock) =>
          @Cypress.trigger("before:window:load", newWindow)
          onSetTimeout = @sandbox.spy()
          newWindow.setTimeout(onSetTimeout)
          clock.tick()
          expect(onSetTimeout).to.be.called

    context "logging", ->
      beforeEach ->
        @logs = []
        @Cypress.on "log", (attrs, log) =>
          @logs.push(log)

      it "logs when created", ->
        @cy.clock().then =>
          log = @logs[0]
          expect(@logs.length).to.equal(1)
          expect(log.get("name")).to.eq("clock")
          expect(log.get("message")).to.eq("")
          expect(log.get("type")).to.eq("parent")
          expect(log.get("state")).to.eq("passed")
          expect(log.get("snapshots").length).to.eq(1)
          expect(log.get("snapshots")[0]).to.be.an("object")

      it "logs when restored", ->
        @cy.clock().then (clock) =>
          clock.restore()

          log = @logs[1]
          expect(@logs.length).to.equal(2)
          expect(log.get("name")).to.eq("restore")
          expect(log.get("message")).to.eq("")

      it "does not log when auto-restored", (done) ->
        @cy.clock().then =>
          @Cypress.trigger("restore")
          expect(@logs.length).to.equal(1)
          done()

      it "does not log when log: false", ->
        @cy.clock({log: false}).then (clock) =>
          clock.tick()
          clock.restore()
          expect(@logs.length).to.equal(0)

      it "only logs the first call", ->
        @cy
          .clock()
          .clock()
          .clock()
          .then =>
            expect(@logs.length).to.equal(1)

      context "#consoleProps", ->
        beforeEach ->
          @cy.clock(100, ["setTimeout"]).then (@clock) ->
            @clock.tick(100)

        it "includes clock's now value", ->
          consoleProps = @logs[1].attributes.consoleProps()
          expect(consoleProps["Now"]).to.equal(200)

        it "includes methods replaced by clock", ->
          consoleProps = @logs[1].attributes.consoleProps()
          expect(consoleProps["Methods replaced"]).to.eql(["setTimeout"])

        it "logs ticked amount on tick", ->
          createdConsoleProps = @logs[0].attributes.consoleProps()
          expect(createdConsoleProps["Ticked"]).to.be.undefined
          tickedConsoleProps = @logs[1].attributes.consoleProps()
          expect(tickedConsoleProps["Ticked"]).to.equal("100 milliseconds")

        it "properties are unaffected by future actions", ->
          @clock.tick(100)
          @clock.restore()
          consoleProps = @logs[1].attributes.consoleProps()
          expect(consoleProps["Now"]).to.equal(200)
          expect(consoleProps["Methods replaced"]).to.eql(["setTimeout"])

  describe "#tick", ->
    it "moves time ahead and triggers callbacks", (done) ->
      @cy
        .clock()
        .then =>
          @window.setTimeout ->
            done()
          , 1000
        .tick(1000)

    it "returns the clock object", ->
      @cy
        .clock()
        .tick(1000).then (clock) ->
          expect(clock).to.equal(@clock)

    context "errors", ->
      beforeEach ->
        @allowErrors()

      it "throws if there is not a clock", (done) ->
        @cy.on "fail", (err) ->
          expect(err.message).to.equal("cy.tick() cannot be called without first calling cy.clock()")
          done()

        @cy.tick()

      it "throws if ms is not undefined or a number", (done) ->
        @cy.on "fail", (err) ->
          expect(err.message).to.equal("clock.tick()/cy.tick() only accept a number as their argument. You passed: \"100\"")
          done()

        @cy.clock().tick("100")

    context "logging", ->
      beforeEach ->
        @logs = []
        @Cypress.on "log", (attrs, log) =>
          @logs.push(log)

      it "logs number of milliseconds", ->
        @cy
          .clock()
          .tick(250)
          .then =>
            log = @logs[1]
            expect(@logs.length).to.equal(2)
            expect(log.get("name")).to.eq("tick")
            expect(log.get("message")).to.eq("250ms")

      it "logs before and after snapshots", ->
        @cy
          .clock()
          .tick(250)
          .then =>
            log = @logs[1]
            expect(log.get("snapshots").length).to.eq(2)
            expect(log.get("snapshots")[0].name).to.equal("before")
            expect(log.get("snapshots")[1].name).to.equal("after")
