package Object::Remote::Logging;

use strictures 1;

use Object::Remote::LogRouter;
use Object::Remote::LogDestination;
use Log::Contextual::SimpleLogger;
use Carp qw(cluck);

use base qw(Log::Contextual); 

sub arg_router {
  return $_[1] if defined $_[1]; 
  our $Router_Instance;
 
  return $Router_Instance if defined $Router_Instance; 
 
  $Router_Instance = Object::Remote::LogRouter->new(
    description => $_[0],
  );
}

sub init_logging {
  my ($class) = @_; 
  our $Did_Init;
    
  return if $Did_Init;
  $Did_Init = 1; 
    
  if ($ENV{OBJECT_REMOTE_LOG_LEVEL}) {
    $class->init_logging_stderr($ENV{OBJECT_REMOTE_LOG_LEVEL});
  }
}

sub init_logging_stderr {
  my ($class, $level) = @_;
  our $Log_Level = $level;
  chomp(my $hostname = `hostname`);
  our $Log_Output = Object::Remote::LogDestination->new(
    logger => Log::Contextual::SimpleLogger->new({ 
      levels_upto => $Log_Level,
      coderef => sub { 
        my @t = localtime();
        my $time = sprintf("%0.2i:%0.2i:%0.2i", $t[2], $t[1], $t[0]);
        warn "[$hostname $$] $time ", @_ 
      },
    })
  );
  $Log_Output->connect($class->arg_router);
}

sub init_logging_forwarding {
#  my ($class, $remote_parent) = @_; 
#  chomp(my $host = `hostname`);
#  $class->arg_router->description("$$ $host");
#  $class->arg_router->parent_router($remote_parent);
#  $remote_parent->add_child_router($class->arg_router);
}

1;

#__END__
#
#Hierarchical routed logging concept
#
#  Why?
#  
#  Object::Remote and systems built on it would benefit from a standard model
#  for logging that enables simple and transparent log generation and consumption
#  that can cross the Perl interpreter instance boundaries transparently. More 
#  generally CPAN would benefit from a common logging framework that allows all
#  log message generators to play nicely with all log message consumers with out
#  making the generators or consumers jump through hoops to do what they want to do. 
#  If these two solutions are the same then all modules built using the
#  logging framework will transparently operate properly when run under Object::Remote.
#  
#  Such a solution needs to be flexible and have a low performance impact when it is not
#  actively logging. The hiearchy of log message routers is the way to achieve all of these
#  goals. The abstracted message router interface introduced to Log::Contextual allows 
#  the hierarchical routing system to be built and tested inside Object::Remote with possible
#  larger scale deployment in the future.
#  
#  Hierarchy of log routers
#  
#    * Each Perl module ideally would use at least a router dedicated
#      to that module and may have child routers if the module is complex.
#    * Log messages inserted at low levels in the hierarchy
#      are available at routers at higher levels in the hierarchy.
#    * Each running Perl instance has a root router which receives
#      all log messages generated in the Perl instance.
#    * The routing hierarchy is available for introspection and connections
#      from child routers to parent routers have human readable strings
#    * The entire routing system is dynamic
#       * Add and remove routers while the system is in operation
#       * Add and remove taps into routers while the system is in operation
#    * Auto-solves Object::Remote logging by setting the parent router of the
#      root router in the remote instance to a router in the local instance the
#      log messages will flow into the local router via a proxy object
#       * Should probably be two modes of operation for Object::Remote logging
#          * forwarding across instances for ease of use during normal operation
#          * stderr output by default for debugging cases to limit the usage of
#            object::remote   
#
#
#  Example hiearchy
#  
#     Root                [1]
#       * System::Introspector
#       * Object::Remote  [2]
#          * local        [3]
#          * remote       [4]
#             * hostname-1.example.com [5]
#                * Root
#                   * System::Introspector
#                   * Object::Remote
#                      * local
#             * hostname-2.example.com
#                 * Root
#                   * System::Introspector
#                   * Object::Remote
#                      * local
#    
#      [1] This router has all logs generated anywhere
#          even on remote hosts        
#      [2] Everything related to Object::Remote including
#          log messages from remote nodes for things other
#          than Object::Remote     
#      [3] Log messages generated by Object::Remote on the local
#          node only        
#      [4] All log messages from all remote nodes    
#      [5] This is the connection from a remote instance to the
#          local instance using a proxy object
#
#      As a demonstration of the flexibility of the this system consider a CPAN testers GUI 
#      tool. This hypothetical tool would allow a tester to select a module by name and perform
#      the automated tests for that package and all dependent packages. Inside the tool is a pane for
#      the output of the process (STDOUT and STDERR), a pane for log messages, and a pane displaying
#      the modules that are participating in routed logging. The tester could then click on individual
#      packages and enable logging for that package dynamically. If neccassary more than one package
#      could be monitored if neccassary. If the GUI is wrapping a program that runs for long periods of
#      time or if the application is a daemon then being able to dynamically add and remove logging
#      becomes very useful.
#   
#   Log message selection and output
#   
#      * Assumptions
#         * Modules and packages know how they want to format log messages
#         * Consumers of log messages want to know
#            * Which Perl module/package generated that message
#            * When running with Object::Remote if the log message is from
#              a remote node and if so which node
#         * Consuming a log message is something the consumer knows how it wants
#           to be done; the module/package should not be dictating how to receive
#           the log messages
#         * Most log messages most of the time will be completely ignored and unused
#       * Router taps
#          * A consumer of log messages will tap into a router at any arbitrary point
#            in the router hierarchy even across machines if Object::Remote is involved
#          * The tap is used to access a stream of log data and is not used to select
#            which packages/modules should be logged
#             * For instance Object::Remote has log messages flowing through it that 
#               include logs generated on remote nodes even if those logs were generated
#               by a module other than Object::Remote
#       * Selection
#          * The module has defined what the log message format is
#          * The tap has defined the scope of messages that will be 
#            available for selection, ie: all log messages everywhere,
#            all logs generated on Object::Remote nodes, etc
#          * Selection defines what log messages are going to be delivered
#            to a logger object instance
#             * Selectors act as a gate between a tap and the logger object
#             * Selectors are closures that perform introspection on the log
#               message; if the selector returns true the logger will be invoked
#               to log this message
#             * The logger still has a log level assigned to it and still will have
#               the is_$level method invoked to only log at that specific level
#       * Destinations
#          * A log destination is an instance of a logger object and the associated
#            selectors.
#          * Consuming logging data from this system is a matter of
#             * Constructing an instance of a logging destination object which has
#               the following attributes:
#                * logger - the logger object, like warnlogger or log4perl instance
#                * selectors - a list of closures; the first one that returns true
#                              causes the logger to be checked for this log_level and
#                              invoked if neccassary 
#          * Register selectors with the destination by invoking a method and specifying
#            sub refs as an argument 
#      
#   Technical considerations
#      * Log contextual likes to have the logger invoked directly inside the exported log
#        specific methods because it removes a need to muck with logger caller depths to
#        report back the proper caller information for the logger.
#         * Because of this the best strategy identified is to return a list of loggers
#           to those exported methods which then invoke the loggers inside the method
#         * This means that log message forwarding is a process of querying each parent
#           router for a list of logger objects that should be invoked. Each router along
#           the hierarchy adds to this list and the log_* method will invoke all loggers
#           directly. 
#      * The routing hierarchy has cycles where parent routers hold a reference to the child
#        and the child holds a reference to the parent. The cycles are not a problem if weak
#        references are used however proxy objects don't seem to currently work with weak
#        references. 
#      * Once a logger hits a proxy object the caller information is totally blown; this
#        crossing isn't transparent yet
#       
#       
#       




