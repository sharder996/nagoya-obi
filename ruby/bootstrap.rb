# Set up the environment
# Define some RUBYSCRIPT2EXE constants
module RUBYSCRIPT2EXE
  RUBYEXE	= 'ruby.exe'
  COMPILED	= true
  USERDIR	= Dir.pwd
end
dir	= File.expand_path(File.dirname(__FILE__))
bin		= dir + '/bin'
lib		= dir + '/lib'
verbose	= $VERBOSE
$VERBOSE	= nil
s		= ENV['PATH'].dup
$VERBOSE	= verbose
if Dir.pwd[1..2] == ':/'
  s.replace(bin.gsub(/\//, '\\')+';'+s)
else
  s.replace(bin+':'+s)
end
ENV['PATH']   = s
$:.clear
$: << lib
require 'rbconfig'
Config::CONFIG['archdir']		= dir + '/lib'
Config::CONFIG['bindir']		= dir + '/bin'
Config::CONFIG['datadir']		= dir + '/share'
Config::CONFIG['datarootdir']		= dir + '/share'
Config::CONFIG['docdir']		= dir + '/share/doc/$(PACKAGE)'
Config::CONFIG['dvidir']		= dir + '/share/doc/$(PACKAGE)'
Config::CONFIG['exec_prefix']		= dir + ''
Config::CONFIG['htmldir']		= dir + '/share/doc/$(PACKAGE)'
Config::CONFIG['includedir']		= dir + '/include'
Config::CONFIG['infodir']		= dir + '/share/info'
Config::CONFIG['libdir']		= dir + '/lib'
Config::CONFIG['libexecdir']		= dir + '/libexec'
Config::CONFIG['localedir']		= dir + '/share/locale'
Config::CONFIG['localstatedir']	= dir + '/var'
Config::CONFIG['mandir']		= dir + '/share/man'
Config::CONFIG['pdfdir']		= dir + '/share/doc/$(PACKAGE)'
Config::CONFIG['prefix']		= dir + ''
Config::CONFIG['psdir']		= dir + '/share/doc/$(PACKAGE)'
Config::CONFIG['rubylibdir']		= dir + '/lib'
Config::CONFIG['sbindir']		= dir + '/sbin'
Config::CONFIG['sharedstatedir']	= dir + '/com'
Config::CONFIG['sitearchdir']		= dir + '/lib'
Config::CONFIG['sitedir']		= dir + '/lib'
Config::CONFIG['sitelibdir']		= dir + '/lib'
Config::CONFIG['sysconfdir']		= dir + '/etc'
Config::CONFIG['topdir']		= dir + '/lib'
# Load eee.info
eeedir		= File.dirname(__FILE__)
eeeinfo		= File.expand_path('eee.info', eeedir)
if File.file?(eeeinfo)
  lines	= File.open(eeeinfo){|f| f.readlines}
  badline	= lines.find{|line| line !~ /^EEE_/}
  while badline
    pos		= lines.index(badline)
    raise 'Found badline at position 0.'	if pos == 0
    lines[pos-1..pos]	= lines[pos-1] + lines[pos]
    badline		= lines.find{|line| line !~ /^EEE_/}
  end
  lines.each do |line|
    k, v	= line.strip.split(/ *= */, 2)
    k.gsub!(/^EEE_/, '')
    v	= File.expand_path(v)	if k == 'APPEXE'
    RUBYSCRIPT2EXE.module_eval{const_set(k, v)}
  end
  ARGV.concat(RUBYSCRIPT2EXE::PARMSLIST.split(/ /))
end
# Start the application
load($0 = ARGV.shift)
