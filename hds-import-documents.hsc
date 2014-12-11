=setup

[Configuration]
ListFileExtension = TXT

[Window]
Name = HAS
Head = Import Thiess Documents


[Labels]
DIR     = END   2 10 Import Folder
OUT     = END   +0 +1 Report Output

[Fields] 
DIR     = 3   10 INPUT   CHAR       40  0  FALSE   FALSE  0.0 0.0 '' $PA
OUT     = +0   +1 INPUT   CHAR       10  0  FALSE   FALSE  0.0 0.0 'S' $OP

[Perl]

[Todo]
* if site not registered throw email error
* if date unlikely throw email error
* can we recognise file type (e.g. logger file, and then import with PROLOG?
* If not then send to html error rerpot which gets sent to the nomiated user.

=cut


=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

  This HYSCRIPT imports documents to the Hydstra Documents Folder which follow the standard naming convention 
  
=cut

=head1 Naming convention
  
  File Naming conventions from Thiess Procedure: 
    TSEV-036390-OPS-PR-039 - Hydrographic Metadata.doc

  4.3.1	Continuous Monitoring Logger Files
  [Site Number]_[Date (YYYYMMDD)]_[Instrument Type (abbreviated)].[Incremental Number]
    e.g. 405123A_20131029_CAM.A23

  4.3.2	Calibration Records
  [Site Number]_[Date (YYYYMMDD)]_[Report Number]_[Serial Number]
    e.g. 405123A_20131029_M400123_L4123
  
  4.3.3	Staff gauge Surveys
  [Site Number]_[Date (YYYYMMDD)]_[Report Number]
    e.g. 405123A_20131029_M500123.pdf

  4.3.4	Hydrographic Station Photos
  [Site Number]_[Date (YYYYMMDD)]_[Photo Type]_[Photo number (if more than one)]
    e.g. 405123A_20131029_CO_01.jpeg

    
  Logger File	
    [Site Number]_[Date (YYYYMMDD)] _[Instrument Type (abbreviated)] [Incremental Number]	
      e.g 405123A_20131029_CAM.A23
  
  Calibration Records	
    [Site Number]_[Date (YYYYMMDD)]_[Report Number]_[Serial Number]	
      e.g 405123A_20131029_M400123_L4123
  
  Staff Gauge Survey	
    [Site Number]_[Date (YYYYMMDD)]_[Report Number]	
      e.g. 405123A_20131029_M500123.pdf
  
  Installation Change Notice Forms	
    [Site Number]_[Date (YYYYMMDD)]_[Form Number]	
    e.g. 405123A_20131029_TSEV-036390-OPS-FO-034.xls  
  
=cut

use strict;
use warnings;

use Data::Dumper;
use FileHandle; 
use DateTime;
use Time::localtime;

use Env;
use File::Copy;
use File::stat;
use File::Path qw(make_path remove_tree);
use File::Fetch;
use Try::Tiny;
use Cwd;

use FindBin qw($Bin);

## Kisters modules
use HyTSFile;

## Kisters libraries
require 'hydlib.pl';
require 'hydtim.pl';

## HDS Modules
#use local::lib "$Bin/HDS/";
use local::lib "C:/Hydstra/hyd/dat/ini/HDS/";
#use Export::dbf;
use Hydstra;
use Import;
use Import::fs;
use Import::History;

  


## Globals
my $prt_fail = '-P';


main: {
  
  my ($dll,$use_hydbutil,%ini,%temp,%errors);
  
  
  
  
  
  #Get config values
  my $inipath       = HyconfigValue('INIPATH');
  my $temp          = HyconfigValue('TEMPPATH');
  my $junk          = HyconfigValue('JUNKPATH').'documents\\';
  my $docpath       = HyconfigValue('DOCPATH');
  my $quarantine    = $temp.'\\quarantine_documents\\';
  my $workarea = 'priv.histupd';
  my $hdspath = $inipath.'HDS\\';
  MkDir($quarantine);
  MkDir($junk);
  
  #Gather parameters and config
  my $script     = lc(FileName($0));
  Prt('-P',"Script [$script] hdspath [$hdspath]\n");
  
  IniHash($ARGV[0],\%ini, 0, 0);
  IniHash($hdspath.$script.'.ini',\%ini, 0 ,0);
  
  
  
  #Gather parameters
  my %photo_types   = %{$ini{'photo_types'}};
  my %emails        = %{$ini{'email_setup'}};
  my $import_dir    = $ini{perl_parameters}{dir};  
  #my $reportfile    = $ini{perl_parameters}{out};  
  my $reportfile    = $junk."output.txt";  
  my $printfile    = $junk."printfile.txt";  
  my $nowdat = substr (NowString(),0,8); #YYYYMMDDHHIIEE to YYYYMMDD for default import date
  my $nowtim = substr (NowString(),8,4); #YYYYMMDDHHIIEE to HHII for default import time
  
  my $fs = Import::fs->new();
  my $ts=HyTSFile->New();  #initialise object 
  
  my @files = $fs->FList($import_dir,'*');
  shift @files;
  
  Prt('-P',"files [".HashDump(\@files)."]");

  PrintAndRun('-S',qq(HYDBUTIL DELETE [$workarea]history "$printfile" /FASTMODE) );
  
  open my $io, ">>", $reportfile;
  if ( $#files < 0 ) {
    Prt('-X',"no files");
  }
  else{
    foreach ( @files ) {

      my @file_dir = split(/\//,$_);
      my $file_name = $file_dir[$#file_dir];
      $file_name =~ s{( |-|~)}{_}gi;
      
      my @file_components = split(/_/,$file_name);
      my $site = $file_components[0]; 
      my $date = $file_components[1]; 
      
      my $valid = 1;
      my $reason = '';
      my $destination;
      
      if ( ! ( $ts->ValidSite($site)) ){
        print "*** ERROR - [$site] is not valid naming convention\n";
        $destination = $quarantine.$file_name;
        $errors{invalid}{$site}{filename} = $file_name;
        $errors{invalid}{$site}{reason} = "not valid naming convention";
        next;
      }
      elsif ( ! ( $ts->SiteExists($site)) ){
        print "*** ERROR - [$site] does not exist in site table\n";
        $errors{invalid}{$site}{filename} = $file_name;
        $errors{invalid}{$site}{reason} = "does not exist in site table";
        next;
      }    
      else{
        my $site_docpath = $docpath.'SITE\\'.$site.'\\';
        MkDir( $site_docpath );
        $destination = $site_docpath.$file_name;
        $temp{$site}{file_name}{$file_name}++;
        $temp{$site}{file_path}{$destination}++;
      }
      
      if ( copy( $_, $destination ) ) {
        print NowStr()."   - Saved to [$destination]\n";  
      }
      else {
        Prt($prt_fail,NowStr() . "   *** ERROR - Copy [$_] Failed\n" );
        $errors{copy_fail}{$site}{files}{$_}++;
      }
    }
    
    $ts->Close;                                                    #close the object 

    unlink (@files);  
    
    if ( defined ( $errors{invalid} )){
      print $io "IMPORT DOCUMENTS ERROR REPORT\n";
    }
    else{
      my %hist = ();
      foreach my $site ( keys %temp ){
        my $descript = "Documents Import:\n";
        foreach my $file ( keys %{$temp{$site}{file_name}} ){
          $descript .= "$file\n";
        }  
        $hist{$site.'doc'}{DESCRIPT}     = $descript;
        $hist{$site.'doc'}{STATDATE}     = $nowdat;
        $hist{$site.'doc'}{STATTIME}     = $nowtim;
        $hist{$site.'doc'}{KEYWORD}      = 'DOCUMENTS';
        $hist{$site.'doc'}{STATION}      = $site;
        
=skip        
        my %descript = ();
        foreach my $file ( keys %{$temp{$site}{file_path}} ){
          next if ( ! $image->image_file($file) );
          my $base64 = filetobase64($file);
          my %file = ();
          $file{"base64"} = $base64;
          $file{"type"}   = $file_type;
          push ( @{$descript{files}, \%file );
        }  
        
        my $descript = jsontostr(HashToJSON(%descript ));
        
        $hist{$site.'base64'}{DESCRIPT}     = $descript;
        $hist{$site.'base64'}{STATDATE}     = $nowdat;
        $hist{$site.'base64'}{STATTIME}     = $nowtim;
        $hist{$site.'base64'}{KEYWORD}      = 'BASE64';
        $hist{$site.'base64'}{STATION}      = $site;
=cut      
      }  
      
      my $rep = 'C:\\temp\\history_report.txt';
      
      my %params;
      my $history = Import::History->new();
      $history->update({'workarea'=>$workarea,'history'=>\%hist,'params'=>\%params});
    }  
    
    
  }    
  close ($reportfile);
  
  my $wk = '['.$workarea.']history';
  Prt('-P',"wk [$wk]");
  PrintAndRun('-S',qq(HYDBUTIL APPEND HISTORY $wk TABLE YES "$printfile" /FASTMODE) ) ;
  
  try {
  }
  catch {
    print "error updating HISTORY";
    Prt('-P',"hello world");
    
  }
    
  
  
  #Archive work area
  #PrintAndRun(HYDBUTIL DELETE history [PUB.$workarea]history "$rep" /FASTMODE);
  
  #Email any issues to the nominated users
  #copied files
  #SITE | FROM | TO | STATUS
  #--------------------------
  # 220110  | C:\temp\user\smaud\file.pdf| documents\SITE\ | success
  # 220110A |
  
  #error_report = create_error_report(\%errors); 
  #send_report($error_report); 
  #zd d
  
}

1; # End of importer
