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
#use Time::localtime;
use Env;
use File::Copy;
use File::stat;
use File::Path qw(make_path remove_tree);
use File::Fetch;
use Try::Tiny;
use Cwd;

use FindBin qw($Bin);

#Hydrological Administration Services Modules
use local::lib "$Bin/HAS/";
use Export::dbf;
#use Existence::Site;
use Hydstra;
use Import;
use Import::fs;
use Import::History;

#Hydstra modules
#use HydDLLp;

#Hydstra libraries
require 'hydlib.pl';
require 'hydtim.pl';

#Globals
my $prt_fail = '-P';


main: {
  
  my ($dll,$use_hydbutil,%ini,%temp,%errors);
  
  #Gather parameters and config
  my $script     = lc(FileName($0));
  IniHash($ARGV[0],\%ini, 0, 0);
  IniHash($script.'.ini',\%ini, 0 ,0);
  
  #Get config values
  my $temp          = HyconfigValue('TEMPPATH');
  my $junk          = HyconfigValue('JUNKPATH').'documents\\';
  my $docpath       = HyconfigValue('DOCPATH');
  my $quarantine    = $temp.'\\quarantine_documents\\';
  MkDir($quarantine);
  MkDir($junk);
  
  #Gather parameters
  my %photo_types   = %{$ini{'photo_types'}};
  my %emails        = %{$ini{'email_setup'}};
  my $import_dir    = $ini{perl_parameters}{dir};  
  #my $reportfile    = $ini{perl_parameters}{out};  
  my $reportfile    = $junk."output.txt";  
  my $nowdat = substr (NowString(),0,8); #YYYYMMDDHHIIEE to YYYYMMDD for default import date
  my $nowtim = substr (NowString(),8,4); #YYYYMMDDHHIIEE to HHII for default import time
  my $fs = Import::fs->new();

  
  try{
    $dll=HydDllp->New();
  }
  catch{
    Prt($prt_fail,NowStr().": *** ERROR An error occured while initialising HYDDLLP\n");
    $use_hydbutil=1;
    
  };
  #Prt($prt_fail,NowStr().": docpath [$docpath] import_dir [$import_dir] photo_types []\n"); #.Dumper(%photo_types)."]\n");

  my @files = $fs->FList($import_dir,'*');
  shift @files;
  if ( $#files < 1 ) {
    Prt('-P',"no files");
  }
  else{
    foreach ( @files ) {
      #open my $fh, "<:encoding(utf8)", $_;
      my @file_dir = split(/\//,$_);
      my $file_name = $file_dir[$#file_dir];
      $file_name =~ s{( |-|~)}{_}gi;
      
      my @file_components = split(/_/,$file_name);
      my $site = $file_components[0]; 
      my $date = $file_components[1]; 
      
      my $siteref = $dll->JSonCall({
          'function' => 'get_db_info',
          'version' => 3,
          'params' => {
              'table_name'  => 'site',
              'field_list'  => ['station', 'stname'],
              'sitelist_filter' => $site,
              'return_type' => 'hash'
          }
      }, 1000000);
      
      
      my $valid = 1;
      my $reason = '';
      if ( ! defined ( $siteref->{return} )){
        Prt('-P',"Not Defined [".HashDump($siteref)."]"); 
        $valid = 0;
        $reason = "Site [$site] not registered in SITE table. Please register in table and re-import the documents";
        
      }
      else{
        my $stname = $siteref->{return}->{rows}->{$site}->{stname};
        
      }
   
      
      my $destination;
      if ( ! $valid ){
        $destination = $quarantine.$file_name;
        $errors{invalid}{$site}{filename} = $destination;
        $errors{invalid}{$site}{reason} = $reason;
      }
      else{
        my $site_docpath = $docpath.'SITE\\'.$site.'\\';
        MkDir( $site_docpath );
        $destination = $site_docpath.$file_name;
        $temp{$site}{file_name}{$file_name}++;
        $temp{$site}{file_path}{$destination}++;
      }
      
      #if site not registered throw email error
      #if date unlikely throw email error
      #can we recognise file type (e.g. logger file, and then import with PROLOG?
      #If not then send to html error rerpot which gets sent to the nomiated user.
  
      if ( copy( $_, $destination ) ) {
        print NowStr()."   - Saved to [$destination]\n";  
      }
      else {
        Prt($prt_fail,NowStr() . "   *** ERROR - Copy [$_] Failed\n" );
      }
     
    }
    unlink (@files);  
    
    if ( defined ( $errors{invalid} )){
      open my $io, ">>", $reportfile;
      
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
      }  
      
      my $rep = 'C:\\temp\\history_report.txt';
      
      my %params;
      my $history = Import::History->new();
      $history->update({'history'=>\%hist,'params'=>\%params});
    }  
    
    close ($reportfile);
    
  }    
  
  #Archive work area
  #PrintAndRun(HYDBUTIL DELETE history [PUB.$workarea]history "$rep" /FASTMODE);
  
  #Email any issues to the nominated users
  
  
  #update_history(\%history); 
  #error_report = create_error_report(\%errors); 
  #send_errors($error_report); 
  #zd
  
}

1; # End of importer
