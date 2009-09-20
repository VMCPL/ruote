#--
# Copyright (c) 2005-2009, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++


require 'ruote/engine/context'


module Ruote

  #
  # A help class for WorkQueue. Used from Workqueue#subscribe
  #
  class BlockSubscriber

    def initialize (block)
      @block = block
    end

    def receive (eclass, emessage, args)
      @block.call(eclass, emessage, args)
    end
  end

  #
  # Ruote uses a workqueue. All apply/reply/cancel operations are performed
  # asynchronously, one after the other.
  #
  # The heart of ruote is here.
  #
  # See ThreadWorkqueue for the main implementation.
  #
  class Workqueue

    include EngineContext

    def initialize

      @subscribers = { :all => [] }
    end

    def add_subscriber (eclass, subscriber)

      (@subscribers[eclass] ||= []) << subscriber

      subscriber
    end

    def subscribe (eclass, &block)

      add_subscriber(eclass, BlockSubscriber.new(block))
    end

    def remove_subscriber (subscriber)

      @subscribers.values.each { |v| v.delete(subscriber) }
    end

    # Emits event for immediate processing (no queueing). This is used
    # for persistence events (the expression wants its state to be persisted
    # ASAP.
    #
    def emit! (eclass, emsg, eargs)

      process([ eclass, emsg, eargs ])
    end

    protected

    def process (event)

      begin

        eclass, emsg, eargs = event

        #
        # using #send, so that protected #receive are OK

        os = @subscribers[eclass]
        os.each { |o| o.send(:receive, eclass, emsg, eargs) } if os

        @subscribers[:all].each { |o| o.send(:receive, eclass, emsg, eargs) }

      rescue Exception => e

        # TODO : rescue for each subscriber, don't care if 1+ fails,
        #        send to others anyway

        p [ :wqueue_process, e.class, e ]
        puts e.backtrace
      end
    end
  end
end

