#! /usr/bin/perl

# blip.pl  blip = the sound of the scanner acknowledging a scan.

# April 18, 2006  ### new USUlogo, more organized display for census
#
# previous version of Feb 23 2006 modified to include cage_type now added to end of record
#                                 in lamTxtFile.txt

#---------------------------------------------------------------------------------------------------------#
# This app obtains info from a hand-held scanning device, determines if more information is needed or     #
# if enough information is available to make a transaction.                                               #
#---------------------------------------------------------------------------------------------------------#
#
# The big outside loop is:
#             "What function is being performed? Census or Deactivate.
# The major inside loop of each big outside loop is:
#             "What type of scan information just got received?
#              Badge, Room or Cage?
#
#              If all needed information for a transaction exists, then do the transaction.
#              Otherwise, set the HTML to obtain the next practical piece of information.
#
#
# If more information is needed, the HTML redisplay contains a prompt for the
# additional information.
#
# If enough information exists to perform a transaction, the transaction gets performed.
# The HTML redisplay indicates the transaction has been performed and prompts for 
# the next tidbit of information to be scanned.
 
# structure of the HTML redisplay:
# <HEAD>  
#        big colors with a phrase describing the action being performed
# <BODY>
#        an HTML form that shows
#               - who is doing the action
#               - a 2-column 3-row table that shows partial info that has been obtained
#                 and prompts for additional information needed to perform a transaction
#               - a status button
#               - an exit button

use CGI qw(:standard);
use Time::localtime;
use Net::FTP;

# These fields are obtained from cage_srch
$cage_num        = '';
$room_num        = '';
$investigator    = '';
$co_investigator = '';
$specie          = '';
$strain          = '';
$sex             = ''; 
$animal_id       = '';
$count_num       = '';
$rec_date        = '';
$apn_num         = '';
$cost_code       = '';
$vendor_code     = '';
$rate_level      = ''; 
$IEB_timestamp   = '';
$cage_type       = '';

# These vars make the HTML template appear semi-dynamic.
$display_date  = '';        
$scan_action   = '';
$row1          = '';
$row2          = '';
$row3          = '';
$row4          = '';
$hidden_values = '';
$wd_day        = 5;   # Friday
$button_line   = '';
$blip_isa      = '';
$cage_prefix   = '';
$USU_badge_prefix = '2130600045';  
$use_javascript = '';
$nrbc           = '';   # need room before cage
$javascript_census_check = "
<script language=\"JavaScript\">
<!--
function check_census(form)
{
  var validated = true;
  if (document.scanner_form.Q1.value == document.scanner_form.Q2.value)
  {
    return validated;
  } else {
    validated = false;
    alert ('Mismatched Counts');
    return validated;
  }
}
//-->
</script>
";


$javascript_euthanize_check = "
<script language=\"JavaScript\">
<!--

function check_euth_quantity(form)
{
  var validated = true;
  if (document.scanner_form.E1.value == document.scanner_form.E2.value)
  {
    return validated;
  } else {
    validated = false;
    alert ('Mismatched Quantitiy');
    return validated;
  }
}
//-->
</script>
";

# Get information from HTML

$blip            = '';
$function_action = '';
$person_scanning = '';
$badge           = '';
$EUTH_badge      = '';
$room_barcode    = '';
$cage_card       = '';
$Q1              = 0;  # Initially Q1 and Q2 need to be different
#$Q2              = '';
$Q2 = -1;
$E1              = 0;  # Initially E1 and E2 need to be different
$E2              = '';
$bingo           = '';  # Whatever was scanned is found in a lookup datafile.


if (param('blip'))            { $blip             = param('blip'); 
                                $blip_length = length($blip);                  }
if (param('function_action')) { $function_action  = param('function_action');  }
if (param('badge'))           { $badge            = param('badge');            }
if (param('EUTH_badge'))      { $EUTH_badge       = param('EUTH_badge');       }
if (param('person_scanning')) { $person_scanning  = param('person_scanning');  }
if (param('room_barcode'))    { $room_barcode     = param('room_barcode');     }
if (param('nrbc'))            { $nrbc             = param('nrbc');             } 
if (param('cage_prefix'))     { $cage_prefix      = param('cage_prefix');      } 
if (param('cage_card'))       { $cage_card        = param('cage_card');        } 
if (param('Q1'))              { $Q1               = param('Q1');               } 
if (param('Q2'))              { $Q2               = param('Q2');               } 
if (param('E1'))              { $E1               = param('E1');               } 
if (param('E2'))              { $E2               = param('E2');               } 

# Global values created in the subs
$OPS_timestamp    = '';
$display_date = '';
$wd           = '';
$census1      = '';
$census2      = '';
$blank        = "&nbsp\;";

# Get timestamp
what_time_is_it(); 

######################## Logic starts here ######################## 
#open (DEBUG, ">>crud.txt");
#print DEBUG "-------\n";
#print DEBUG "blip=$blip\n";
#print DEBUG "function_action=$function_action\n";
#print DEBUG "badge=$badge.\n;
#print DEBUG "EUTH_badge=$EUTH_badge.\n";
#print DEBUG "person_scanning=$person_scanning.\n";
#print DEBUG "room_barcode=$room_barcode.\n";
#print DEBUG "nrbc (need room before cage)=$nrbc.\n";
#print DEBUG "cage_prefix=$cage_prefix.\n";
#print DEBUG "cage_card=$cage_card.\n";
#print DEBUG "Q1=$Q1. Q2=$Q2.\n";
#print DEBUG "E1=$E1. E2=$E2.\n";
# Perform initial parsing of blip
chomp($blip);    # sometimes a lf gets attached to the blip
$f1c = substr($blip,0,1);  # First      character  of scan
$f2c = substr($blip,0,2);  # First two  characters of scan
$f4c = substr($blip,0,4);  # First four characters of scan

$blip_length = length($blip);
if ($blip_length gt 10)
{
  $badge_prefix = substr($blip, 0, 10);
}

#-------------------------------------#
# What just arrived via the scanner?  #
#-------------------------------------#

#-------------------------------------#
# Is the blip a badge?                #
#-------------------------------------#
if (($badge_prefix eq $USU_badge_prefix) || ($f4c eq 'EUTH'))
{
   badge_srch(); 
   $bingo = 'Y';
}

#-----------------------------------------------------------------------------#
# Look at the function_action and determine what to do.
if ($function_action eq 'C')
{
#  if ($blip_isa eq 'badge')
   # Be sure we have a room number before getting a cage number
   if (($blip_isa eq 'badge') || ($nrbc eq 'nrbc'))
  {
  # set html to  acknowledge badge scan and to prompt for room
  #     A       B
  # 1   blip    sumbit (room)
  # 2   blank   blank
  # 3   blank   blank
  # 4   blank   blank
  $hidden_values = "<input type='hidden' name='function_action' value='C'>
                    <input type='hidden' name='person_scanning' value='$person_scanning'>
                    <input type='hidden' name='badge'           value='$badge'>";
  $row1 = "<TR><TD> <input type='text' name='blip' size='1'></TD>
               <TD> <input type='submit' value='Scan a Room'></TD></TR>";
  $row2 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
  $row3 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
  $row4 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
  $bingo = 'Y';
  }
  
  #----------------------#
  # Is the blip a room?  #
  #----------------------#
  # Be sure that blip is not a cage while checking if blip is a room.
  #  (A room scan and a cage scan could both start with 'C' or 'c'.)
  if (($f2c eq 'CA') || ($f2c eq 'ca')  || ($f2c eq 'Ca') || ($f2c eq 'cA') ||
      ($f2c eq 'BC') || ($f2c eq 'Bc')  || ($f2c eq 'bc') || ($f2c eq 'bC') ||
      ($f2c eq 'GC') || ($f2c eq 'Gc')  || ($f2c eq 'cg') || ($f2c eq 'cG'))
  {
    $pig_noise = 'oink';   # Call it anything you want. Just steer it to the ELSE.
  } else {
    if (($f1c eq 'A') || ($f1c eq 'a')  ||
        ($f1c eq 'B') || ($f1c eq 'b')  ||
        ($f1c eq 'C') || ($f1c eq 'c')  ||
        ($f1c eq 'D') || ($f1c eq 'd')  ||
        ($f1c eq 'G') || ($f1c eq 'g'))   
    { 
       room_srch(); 
    }
  }   

  if ($blip_isa eq 'room')
  {
    # set html to acknowledge room scan and to prompt for cage
    #    A        B
    # 1  ROOM     $room_barcode
    # 2  blip     submit
    # 3  blank    blank
    $hidden_values = "<input type='hidden' name='function_action' value='C'>
                      <input type='hidden' name='person_scanning' value='$person_scanning'>
                      <input type='hidden' name='badge'           value='$badge'>
                      <input type='hidden' name='room_barcode'    value='$room_barcode'>";
    $row1 = "<TR><TD>Room:$blank</TD> <TD>$room_barcode</TD></TR>";
    $row2 = "<TR><TD><INPUT type='text' name='blip' size='1'></TD>
                 <TD><INPUT type='submit' value='Scan a cage'</TD></TR>";
    $row3 = "<TR><TD>$blank</TD> <TD> $blank</TD></TR>";
    $row4 = "<TR><TD>$blank</TD> <TD> $blank</TD></TR>";
    $bingo = 'Y';
  }

  #---------------------------#
  # Is the blip a cage card?  #
  #---------------------------#
#  
  if (($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'GCag') || ($f4c eq 'GCAG') || ($f4c eq 'BCag') || ($f4c eq 'BCAG'))
  {
     cage_srch(); 
  }

  if (($blip_isa eq 'cage') && ($room_barcode gt ''))
  {
    # - - - - - - - - - - - - - - - - - #
    # Is it Friday (head-count day) ?   #
    # - - - - - - - - - - - - - - - - - #
    if ($wd ==$wd_day)
    {
      # set html to acknowledge cage scan and prompt for census head-count
      #    A                     B
      # 1  ROOM                  $room_barcode
      # 2  Cage_card             $specie
      # 3  
      # 4  Census  Q1  Q2        Submit
#      $use_javascript = $javascript_census_check;
      $hidden_values = "<input type='hidden' name='function_action' value='C'>
                        <input type='hidden' name='person_scanning' value='$person_scanning'>
                        <input type='hidden' name='badge'           value='$badge'>
                        <input type='hidden' name='room_barcode'    value='$room_barcode'>
                        <input type='hidden' name='cage_prefix'     value='$cage_prefix'>
                        <input type='hidden' name='cage_card'       value='$cage_card'>
                        <input type='hidden' name='specie'          value='$specie'>
                        <input type='hidden' name='count_num'       value='$count_num'>";
      ##
      ## The following group of lines are used twice:
      ## Here and further along in this script if
      ## the double confirmation entry does not match
      ##

      $census1 = "<SELECT NAME='Q1'>
<OPTION VALUE='0'>0</OPTION>
<option VALUE='1'>1</option>
<option VALUE='2'>2</option>
<option VALUE='3'>3</option>
<option VALUE='4'>4</option>
<option VALUE='5'>5</option>
<option VALUE='6'>6</option>
<option VALUE='7'>7</option>
</SELECT>$blank";
      $census2 = "<SELECT NAME='Q2'>
<OPTION VALUE='0'>zero</OPTION>
<option VALUE='1'>one</option>
<option VALUE='2'>two</option>
<option VALUE='3'>three</option>
<option VALUE='4'>four</option>
<option VALUE='5'>five</option>
<option VALUE='6'>six</option>
<option VALUE='7'>seven</option>
</SELECT>$blank";
      $row1 = "<TR><TD>Room$blank$blank</TD> <TD>$room_barcode</TD></TR>";
      $row2 = "<TR><TD>$cage_card$blank$blank</TD> <TD>$specie</TD></TR>";
      $row3 = "<TR></TR>  
               </TABLE>
               <HR>";
      $row4 = "<CENTER>Enter Census Twice</CENTER>
               <TABLE Border='0' CELLSPACING='0' CELLPADDING='0'>
               <TR><TD width='30%'>$census1</TD> 
                   <TD width='30%'>$census2</TD>
                   <TD width='35%' align='top'><input type='submit' name='blip' value='Census' size='1'
                          onClick='check_census(scanner_form)\;' ></TD>
               </TR>";
      $bingo = 'Y'; 
   } else {
      # No. It is not head-count day.
      census_transaction();
      # set html to acknowledge cage scan and prompt for next blip
      #    A                     B
      # 1  ROOM                  $room_barcode
      # 2  Cage_card             $specie
      # 3  blip                  submit
      $hidden_values = "<input type='hidden' name='function_action' value='C'>
                        <input type='hidden' name='person_scanning' value='$person_scanning'>
                        <input type='hidden' name='badge'           value='$badge'>
                        <input type='hidden' name='room_barcode'    value='$room_barcode'>";
      $row1 = "<TR><TD>Room$blank$blank</TD><TD>$room_barcode</TD></TR>";
      $row2 = "<TR><TD>$cage_card$blank$blank</TD><TD>$specie</TD></TR> 
              </TABLE>
              <HR>";
      $row3 = "<TABLE Border='0' CELLSPACING='0' CELLPADDING='0'>
               <TR><TD><INPUT type='text' name='blip' size='1'></TD>
                   <TD><INPUT type='submit' size='1' value='Scan a cage'</TD></TR>";
      $bingo = 'Y';
    }
  }

  #- - - - - - - - - - - - - - - - - - - - - - - #
  # Is blip a cage card BUT the room is unknown? #
  #- - - - - - - - - - - - - - - - - - - - - - - #
  if (($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'GCag') || ($f4c eq 'GCAG') || ($f4c eq 'BCag') || ($f4c eq 'BCAG'))
  {
    if ($room_barcode eq '')
    {
    # set html to TELL that we need a room before we can scan a cage. nrbc="need room before cage"
    #    A                        B
    # 1  
    # 2   SCAN a room BEFORE scanning a CAGE!
    # 3
      $hidden_values = "<input type='hidden' name='function_action'  value='C'>
                        <input type='hidden' name='person_scanning'  value='$person_scanning'>
                        <input type='hidden' name='badge'            value='$badge'>
                        <input type='hidden' name='nrbc'             value='nrbc'>";
      $row1 = "<TR><TD colspan='1'>$blank</TD></TR>";
      $row2 = "<TR><TD colspan='1' align='center'> <FONT COLOR='#FF0000'>SCAN a room BEFORE scanning a cage! </FONT> </TD></TR>";
      $row3 = "<TR><TD><INPUT type='text' name='blip' size='1'></TD>
                   <TD><INPUT type='submit' size='1' value='Scan'</TD></TR>";
      $bingo = 'Y';

    } # end if room is blank
  }   # end if it is a cage AND room is blank

  #- - -- - - - - - - - - - - - - - - - - - -#          
  # Is the blip a head-count quantity?       #
  # And if it is, do both "Q" values match?  #
  #- - - - - - -- - - - - - - - - - - - - - - #
  if (($bingo eq '') && ($Q1 >= 0) && ($Q1 == $Q2))
  {
    # Note: scanner sends zero as blank
 
    # YES. Q1 and Q2 match.  Generate a census transaction.
    census_transaction();
    # set html to acknowledge new census value and to obtain next scan
    #     A            B
    # 1 Room           $room_barcode
    # 2 Cage_card      $specie
    # 3 NEW CENSUS IS  $Q1
    # 4 blip           submit
    $hidden_values = "<input type='hidden' name='function_action' value='C'>
                       <input type='hidden' name='person_scanning' value='$person_scanning'>
                       <input type='hidden' name='badge'           value='$badge'>
                       <input type='hidden' name='room_barcode'    value='$room_barcode'>";
    $row1 = "<TR><TD>Room$blank$blank</TD> <TD>$room_barcode</TD></TR>";
    $row2 = "<TR><TD>$cage_card$blank$blank</TD> <TD>$specie</TD></TR>";
    $row3 = "<TR><TD>New Census is$blank$blank</TD> <TD>$Q1</TD></TR>
             </TABLE>
             <HR>";
    $row4 = "<TABLE Border='0' CELLSPACING='0' CELLPADDING='0'>
             <TR><TD><INPUT type='text' name='blip' size='1'></TD>
                 <TD><INPUT type='submit' value='Scan a cage'</TD></TR>";
    $bingo = 'Y';
   }   # end if (bingo eq '') && (Q1 >= 0) && (Q1 == Q2)
  
   # - - - - - - - - - - - - - - - - - - - -#
   # Is the blip a head-count quantity      #
   # and if it is, do the values NOT match? #
   #- - - - - - - - - - - - - - - - - - - - #
   if (($bingo eq '') && ($Q1 >= 0) && ($Q2 != -1))
   {
     # The quantities do not match. What is wrong with the javascript?
     # The Javascript will notify the scan operator that the quantities are wrong
     # and will ask for new values.  However; the Javascript will still forward
     # the mismatched values to this app. So do a check for mismatched values.
     #
     # Redisplay. 
     # Set html to re-prompt for census head-count
     #    A                     B
     # 1  ROOM                  $room_barcode
     # 2  Cage_card             $specie
     # 3 
     # 4  Census  Q1  Q2        Submit
#       $use_javascript = $javascript_census_check;
     $hidden_values = "<input type='hidden' name='function_action' value='C'>
                       <input type='hidden' name='person_scanning' value='$person_scanning'>
                       <input type='hidden' name='badge'           value='$badge'>
                       <input type='hidden' name='room_barcode'    value='$room_barcode'>
                       <input type='hidden' name='cage_prefix'     value='$cage_prefix'>
                       <input type='hidden' name='cage_card'       value='$cage_card'>
                       <input type='hidden' name='specie'          value='$specie'>
                       <input type='hidden' name='count_num'       value='$count_num'>";
      ##
      ## The following group of lines are used twice:
      ## Here and above in this script if
      ## the double confirmation entry does not match
      ##

      $census1 = "<SELECT NAME='Q1'>
<OPTION VALUE='0'>0</OPTION>
<option VALUE='1'>1</option>
<option VALUE='2'>2</option>
<option VALUE='3'>3</option>
<option VALUE='4'>4</option>
<option VALUE='5'>5</option>
<option VALUE='6'>6</option>
<option VALUE='7'>7</option>
</SELECT>$blank";
      $census2 = "<SELECT NAME='Q2'>
<OPTION VALUE='0'>zero</OPTION>
<option VALUE='1'>one</option>
<option VALUE='2'>two</option>
<option VALUE='3'>three</option>
<option VALUE='4'>four</option>
<option VALUE='5'>five</option>
<option VALUE='6'>six</option>
<option VALUE='7'>seven</option>
</SELECT>$blank";
      $row1 = "<TR><TD>Room$blank$blank</TD> <TD>$room_barcode</TD></TR>";
      $row2 = "<TR><TD>$cage_card$blank$blank</TD> <TD>$specie</TD></TR>";
      $row3 = "<TR></TR>
               </TABLE>
               <HR>";
      $row4 = "<CENTER><FONT COLOR='#FF0000'>Census values MUST MATCH</FONT></CENTER>
               <BR>
               <CENTER>Enter Census Twice</FONT></CENTER>
               <TABLE Border='0' CELLSPACING='0' CELLPADDING='0'>
               <TR><TD width='30%'>$census1</TD> 
                   <TD width='30%'>$census2</TD>
                   <TD width='35%' align='top'><input type='submit' name='blip' value='Census' size='1'
                          onClick='check_census(scanner_form);' ></TD>
               </TR>";
      $bingo = 'Y'; 
    } # end if ($Q2 != Q1)
  
  #----------------------------#
  # Is the blip not resolved?  #
  #----------------------------#
  if ($bingo eq '')
  {
    # Scanned value not found in database (or scan value is fuzzy.)
    # Write whatever was scanned and redisplay last known values. 

    open (ASH, ">> unknown_scan.txt") || die "Unable to open unknown_scan.txt file";
    print ASH "unknown_scan=$blip.time=$OPS_timestamp.badge=$badge.room=$room_barcode.\n";
    close (ASH);
    
    if ($room_barcode gt '')
    {
       # Room barcode exists.  Prompt for rescan of cage card.
       # (They can also scan a badge or room, if they want to.)
       $hidden_values = "<input type='hidden' name='function_action' value='C'>
                         <input type='hidden' name='person_scanning' value='$person_scanning'>
                         <input type='hidden' name='badge'           value='$badge'>
                         <input type='hidden' name='room_barcode'    value='$room_barcode'>";
       $row1 = "<TR><TD colspan='2'>Scanned value is not in database</TD></TR>";
       $row2 = "<TR><TD>$blank</TD><TD>$blank</TD></TR>";
       $row3 = "<TR><TD><INPUT type='text' name='blip' size='1'></TD>
                    <TD><INPUT type='submit' value='Scan'</TD></TR>";
       $row4 = "<TR><TD colspan='2'>$blank</TD></TR>";
    } else {
      # Prompt for a room scan
      #     A       B
      # 1   blip    sumbit (room)
      # 2   blank   blank
      # 3   blank   blank
      # 4   blank   blank
      $hidden_values = "<input type='hidden' name='function_action' value='C'>
                        <input type='hidden' name='person_scanning' value='$person_scanning'>
                        <input type='hidden' name='badge'           value='$badge'>";
      $row1 = "<TR><TD> <input type='text' name='blip' size='1'></TD>
                   <TD> <input type='submit' value='Scan a Room'></TD></TR>";
      $row2 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
      $row3 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
      $row4 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
    }
  }    # end if (bingo eq '')

}      # end if ($function_action eq "C")

#-------------------------------------------------------------------------------#
# --- End of Census function of scanner.----------------------------------------#
#-------------------------------------------------------------------------------#

#-------------------------------------------------------------------------------#
#---- Start of Euthanize data collection function of scanner.-------------------#
#-------------------------------------------------------------------------------#
if ($function_action eq 'X')
{
  #---------------------------------#
  # Is the blip a Euthanize badge?  #
  #---------------------------------#
  if ($blip_isa eq 'EUTH_badge')
  {
    # set html to  acknowledge badge scan and to prompt for cage
    #     A       B
    # 1      EUTHANIZE
    # 2   blip    sumbit (cage)
    # 3   blank   blank
    # 4   blank   blank

    $hidden_values = "<input type='hidden' name='function_action' value='X'>
                      <input type='hidden' name='person_scanning' value='$person_scanning'>
                      <input type='hidden' name='EUTH_badge'      value='$EUTH_badge'>";

    $row1 = "<TR><TD colspan='2' align='center'>EUTHANIZE</TD></TR>";
    $row2 = "<TR><TD> <input type='text' name='blip' size='1'></TD>
                 <TD><input type='submit' value='Scan a CAGE'></TD></TR>";
    $row3 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
    $row4 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
    $bingo = 'Y';
  }

  #----------------------------#
  # Is the blip a cage card?   #
  #----------------------------#
  if (($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'GCag') || ($f4c eq 'GCAG') || ($f4c eq 'BCag') || ($f4c eq 'BCAG'))
  { 
    cage_srch(); 
  }
  
  if ($blip_isa eq 'cage')     
  {
    # set html to acknowledge cage scan and prompt for quantity to euthanize.
    #    A                       B
    # 1       EUTHANIZE
    # 2  Cage_card               $specie
    # 3  Should be quantity      $count_num
    #   - - - - - - - - - - - - - - 
    #   Enter euthanize quantity twice
    # 4  zap1  zap2              Submit (EUTHANIZE)
#    $use_javascript = $javascript_euthanize_check;
    $hidden_values  = "<input type='hidden' name='function_action' value='X'>
                       <input type='hidden' name='person_scanning' value='$person_scanning'>
                       <input type='hidden' name='EUTH_badge'      value='$EUTH_badge'>
                       <input type='hidden' name='cage_prefix'     value='$cage_prefix'>
                       <input type='hidden' name='cage_card'       value='$cage_card'>";
    $zap1 = "<SELECT NAME='E1'>
<OPTION VALUE='0'>0</OPTION>
<option VALUE='1'>1</option>
<option VALUE='2'>2</option>
<option VALUE='3'>3</option>
<option VALUE='4'>4</option>
<option VALUE='5'>5</option>
<option VALUE='6'>6</option>
<option VALUE='7'>7</option>
</SELECT>";
    $zap2 = "<SELECT NAME='E2'>
<OPTION VALUE='0'>zero</OPTION>
<option VALUE='1'>one</option>
<option VALUE='2'>two</option>
<option VALUE='3'>three</option>
<option VALUE='4'>four</option>
<option VALUE='5'>five</option>
<option VALUE='6'>six</option>
<option VALUE='7'>seven</option>
</SELECT>";


    $row1 = "<TR><TD colspan='2' align='center'>EUTHANIZE</TD></TR>";
    $row2 = "<TR><TD>$cage_card$blank$blank</TD> <TD>$specie</TD></TR>";
    $row3 = "<TR><TD>Quantity should be:$blank$blank</TD> <TD>$count_num</TD></TR>
             </TABLE>
             <HR>";
    $row4 = "<CENTER>Enter euthanize quantity twice</CENTER>
             <TABLE Border='0' CELLSPACING='0' CELLPADDING='0'>
             <TR><TD width='30%'>$zap1$blank</TD>
                 <TD width='30%'>$zap2$blank$blank</TD>
                 <TD width='35%'><input type='submit' value='Euthanize' size='1'
                          onClick='check_euth_quantity(scanner_form);' ></TD>
             </TR>";
    $bingo = 'Y';
  } # end if blip_isa eq 'cage'   

  #-----------------------------------------#
  # Is it an  Euthanize quantity?           #  
  # And if it is, do both "E" values match? #
  #-----------------------------------------#


   if ($bingo eq '')
   {
     if ($E1 =>1)
     {
       if (($E1==$E2) || ($E1 eq $E2))
       {
    euthanize_transaction();
    # set html to acknowledge euthanize value and prompt for next scan.
    #    A                     B
    # 1        EUTHANIZE
    # 2  Cage_card             $specie
    # 3  Euthanize Quantity    $E1
    #    - - - - - - - - - - - - - 
    # 4  blip                  Submit
    $hidden_values = "<input type='hidden' name='function_action' value='X'>
                      <input type='hidden' name='person_scanning' value='$person_scanning'>
                      <input type='hidden' name='EUTH_badge'      value='$EUTH_badge'>";
    
    $row1 = "<TR><TD colspan='2' align='center'>EUTHANIZE</TD></TR>";
    $row2 = "<TR><TD>$cage_card </TD> <TD>$specie</TD></TR>";
    $row3 = "<TR><TD>Euthanize Quantity:$blank</TD> <TD>$E1</TD></TR>
             <TR><TD colspan='2'>$blank</TD></TR>";
    $row4 = "<TR><TD><INPUT type='text' name='blip' size='1'></TD>
                 <TD><INPUT type='submit' value='Scan'</TD></TR>";
    # Reset Euthanize Values now that building confirmation display is complete
    $E1 = 0;
    $E2 = '';
    $bingo = 'Y';
 
    } else {
 
  #-----------------------------------------#
  # Mismatched  Euthanize quantity          #  
  #-----------------------------------------#
     # Inform that euthanize values do not match
        # The quantities do not match. What is wrong with the javascript?
        # The Javascript will notify the scan operator that the quantities are wrong
        # and will ask for new values.  However; the Javascript will still forward
        # the mismatched values to this app. So do a check for mismatched values.
        #
        # Redisplay. 
        # Set html to redisplay cage card, quantity that should be there and prompt, again, 
        # for quantity to zap.
        #
        #    A                     B
        # 1        EUTHANIZE
        # 2  Cage_card             $specie
        # 3  
        #    - - - - - - - - - - - - - - 
        #         Values Must MATCH!   <<<appears in RED>>>
        #    Enter euthazize quantity twice
        # 4  Census  Q1  Q2        Submit
#        $use_javascript = $javascript_euthanize_check;
        $hidden_values = "<input type='hidden' name='function_action' value='X'>
                          <input type='hidden' name='person_scanning' value='$person_scanning'>
                          <input type='hidden' name='EUTH_badge'      value='$EUTH_badge'>
                          <input type='hidden' name='cage_prefix'     value='$cage_prefix'>
                          <input type='hidden' name='cage_card'       value='$cage_card'>
                          <input type='hidden' name='specie'          value='$specie'>
                          <input type='hidden' name='count_num'       value='$count_num'>";
        $zap1 = "<SELECT NAME='E1'>
<OPTION VALUE='0'>0</OPTION>
<option VALUE='1'>1</option>
<option VALUE='2'>2</option>
<option VALUE='3'>3</option>
<option VALUE='4'>4</option>
<option VALUE='5'>5</option>
<option VALUE='6'>6</option>
<option VALUE='7'>7</option>
</SELECT>";
        $zap2 = "<SELECT NAME='E2' >
<OPTION VALUE='0'>zero</OPTION>
<option VALUE='1'>one</option>
<option VALUE='2'>two</option>
<option VALUE='3'>three</option>
<option VALUE='4'>four</option>
<option VALUE='5'>five</option>
<option VALUE='6'>six</option>
<option VALUE='7'>seven</option>
</SELECT>";
        $row1 = "<TR><TD colspan='2' align='center'>EUTHANIZE</TD></TR>";
        $row2 = "<TR><TD>$cage_card$blank$blank</TD> <TD>$specie</TD></TR>
                 </TABLE>
                 <HR>";
        $row3 = "<CENTER><FONT COLOR='#FF0000'>Euthanize values MUST MATCH</FONT></CENTER>
                <BR>
                <CENTER>Enter Euthanize Quantity Twice</FONT></CENTER>";
        $row4 = "<TABLE Border='0' CELLSPACING='0' CELLPADDING='0'>
                 <TR><TD width='30%'>$zap1</TD>
                     <TD width='30%'>$zap2</TD>
                     <TD width='35%'><INPUT type='submit' value='Scan'
                          onClick='check_euth_quantity(scanner_form)\;' ></TD>
                 </TR>";
        $bingo = 'Y';  
     } # End if mismatched Euthanize values.
     } # End if $e1>0
   }   # end first if bingo = ''
  #----------------------------------#
  # Is the blip still not resolved?  #
  #----------------------------------#
  if ($bingo eq '')
  {

    # Scanned value not found in database (or scan value is fuzzy.)

    # Write unknown scanned value to a file.
    open (ASH, ">> unknown_scan.txt") || die "Unable to open unknown_scan.txt file";
    print ASH "unknown_scan=$blip.time=$OPS_timestamp.badge=$EUTH_badge.\n";
    close (ASH);

    # Redisplay and prompt for another scan.
    $hidden_values = "<input type='hidden' name='function_action' value='X'>
                      <input type='hidden' name='person_scanning' value='$person_scanning'>
                      <input type='hidden' name='EUTH_badge'      value='$EUTH_badge'>
                      <input type='hidden' name='cage_prefix'     value='$cage_prefix'>
                      <input type='hidden' name='cage_card'       value='$cage_card'>
                      <input type='hidden' name='specie'          value='$specie'>";
    $row1 = "<TR><TD colspan='2' align='center'>EUTHANIZE</TD></TR>";
    $row2 = "<TR><TD colspan='2'>Scanned value is not in database</TD></TR>";
    $row3 = "<TR><TD> <input type='text' name='blip' size='1'></TD>
                 <TD><input type='submit' value='Scan Again'></TD></TR>";
    $row4 = "<TR><TD>$blank</TD> <TD>$blank</TD></TR>";
  }
}    # End if ($function_action eq 'X')
 
#-------------------------------------------------------------------------------#
#------ End of Euthanize data collection function of scanner.-------------------#
#-------------------------------------------------------------------------------#
#close (DEBUG);

html();
# -----------------------------
# ------T H E    E N D --------
# -----------------------------

#---------------------------------------------------------------------------------#

sub what_time_is_it

{
  # This sub creates a timestamp.
  # This sub also determines the day_of_week that is needed if the action = "C"

  $time=localtime;
  $month = $time->mon+1;
  if($month<10){$month = '0' . $month}
  $day = $time->mday;
  if ($day<10){$day = '0' . $day}
  $year = $time->year+1900;
  $hour = $time->hour;
  if ($hour<10){$hour = '0' . $hour}
  $min = $time->min;
  if ($min<10){$min = '0' . $min}
  $sec = $time->sec;
  if ($sec<10){$sec = '0' . $sec}
  $wd = $time->wday; #1=monday 2=tuesday 3=wednesday 4=thursday 5=friday  6=saturday 7=Sunday
                     #1=lunes  2=martes  3=miercoles 4=jueves   5=viernes 6=sabado   7=Domingo

  $OPS_timestamp = join('',$year,$month,$day,$hour,$min,$sec);
  $display_date = join('-', $month, $day, $year);

  # $wd , $OPS_timestamp, and $display_date are global values

} # end sub what_time_is_it
#--------------------------------------#

sub badge_srch
{
  $new_badge = $blip;
  # It could be a regular badge or a EUTH badge.
  # The USU badge number has several leading characters ('2130600045') 
  # prior to the actual badge number. 
  # We are only interested in looking at the unique
  # last 5 digits of a USU Badge number.  (Only the last 4 unique digits if the fifth
  # digit from the end is a zero.)   
  # Either way, use the last 5 (or 4) digits of badge for lookup.

  $lbadge2 = ('0');

  # Get last 5 digits of value obtained by scanner.
  $lbadge5 = substr($new_badge, -5);

  # Strip fifth digit from end if it is zero.
  if ($lbadge2 eq substr($lbadge5, 0, 1))
  {
    $lbadge4 = substr($new_badge, -4);
    $badge   = $lbadge4;
  } else {
    $badge = $lbadge5;
  }
  # Read file obtained from USU Corporate Data Base.
  $file = "oratxfile1.txt";
  open (FILE, "< $file")  || die "Can't open $file: $!";
  @pers_info = <FILE>;               # Read badge file.
  close(FILE);

  @searchinfo = ();                  # Clear the array buffer before using it.
  foreach $line2 (@pers_info)
  {
    chomp($line2);
    @linein2 = split(/\|/,$line2);
#    if($linein2[0] =~ /$badge/i)     # Does badge in record match scanned badge?
    if ($linein2[0] eq $badge)
    {
      #chomp($line2);
      ($badge,$jpg_num,$fname,$mi,$lname,$title,$room,$dep,$bldg,$hphone,$phone,$cphone,$doh)=split(/\|/,$line2);
       $person_scanning = join(" ", $fname, $lname);
      # $function_action = 'C';    # Census
      # $blip_isa        = 'badge';
       # A new badge was found was obtained from the scanner.  Reset known values.
       # These are from a cage card. 
       $cage_prefix     = '';
       $cage_num        = '';
       $room_num        = '';
       $investigator    = '';
       $co_investigator = '';
       $specie          = '';
       $strain          = '';
       $sex             = '';
       $animal_id       = '';
       $count_num       = '';
       $rec_date        = '';
       $apn_num         = '';
       $cost_code       = '';
       $vendor_code     = '';
       $rate_level      = '';
       $IEB_timestamp   = '';
       # These could exist when a new badge gets scanned.
       $room_barcode    = '';
       $cage_card       = '';
       $Q1              = 0; 
       $Q2              = '';
       $E1              = 0;
       $E2              = '';
       $hidden_values   = '';

       # Dont confuse EUTHANIZE badge with CENSUS badge. 
       if ($f4c eq 'EUTH')
       {
         # Set values that only exist if it is a EUTHANIZE badge
         $function_action = 'X';  
         $EUTH_badge = $new_badge;
         $badge      = '';
         $blip_isa   = 'EUTH_badge';
         $E1         = 0;
         $E2         = '';
         $f4c = 'skunk';
       } else {
         # Set values that only exist if it is a regular USU badge
         $function_action = 'C';
         $EUTH_badge = '';
         $blip_isa   = 'badge';

       }     # end if ($f4c eq 'EUTH')

    }        # end if ($linein2[0] matches scanned badge
  }          # end foreach $line2  
}            # end sub badge_srch

#--------------------------------------#

sub room_srch
{
  $room = $blip;

  # This sub compares the room number from scanner with a list of
  # valid lam rooms.  If a match is found everything is OK. 
  # If a  match is not found, then the value of $room_barcode gets set
  # to blank (and such will cause html to prompt for a room, again.)
  # Read file containing LAM Cage rooms.
  $file1 = "lam_room.txt";
  open (FILE1, "< $file1")  || die "Can't open $file1: $!";
  @room_info = <FILE1>;            #There should only be 1 match for room number
  close (FILE1);

  @searchinfo = ();                # Clear the array before using it.
  foreach $line(@room_info)
  {
    chomp($line);
    @linein = $line;
    if($linein[0] =~ /$blip/)
    {
      push (@searchinfo, $line);
      $chunks = @searchinfo;
    }
  }
  if ($chunks > 0)                 # Was a matching room found in the lam_room file?
  {
    $line = @searchinfo[0];
    chomp($line);
    $room_barcode = $blip;    ##### @searchinfo[0];
    $blip_isa = 'room';
  }
} # end sub room_srch
#--------------------------------------#

sub cage_srch
{
  $cage    = $blip;

  # Two formats of cages are in use:
  # First format is original format where CageNumber starts with some upper/lower variation of "CAGE"
  # Second format is where CageNumber is either a "general" cage or a "birthing" cage.
  # Second format CageNumber starts with "B" or "G".

  # Determine which format of CageNumber was scanned.
  if (($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage') ||
      ($f4c eq 'Cage') || ($f4c eq 'CAGE') || ($f4c eq 'cage'))
  {
    $cage_prefix = 'G';    # Force it to "General"
  } else {
    $cage_prefix = substr($cage,0,1);
  }

  # Find position of space
  $cagelen = length($cage);
  $x=0;
  for($i=0; $i<=$cagelen; $i++)
  {
    if (substr($cage,$i,1) eq ' ')
    {
      $x=$i;
      $i=$cagelen;
    }
  }
    
  # Get portion of blip containing a cage card number.
  $x++;
  $cage_card_num = substr($cage, $x, $cagelen);

  # Read file containing current information from LAM system.
  $file3 = 'lamTxtFile.txt';         # File resides in /var/www/html.
  open (FILE3, "< $file3")  || die "Can't open $file3: $!";
  @animal_info = <FILE3>;
  close (FILE3);

  @searchinfo = ();                  # Clear the array before using it
  @linein     = ();

  # Read file from LAM database server.
  foreach $line(@animal_info)
  {
    chomp($line);
    @linein = split(/\|/,$line);
    if($linein[0] eq $cage_card_num)   # File from IEB only has a number, not a prefix.
    {
      push (@searchinfo, $line);
      $chunks = @searchinfo;
    }
  }

  if ($chunks > 0 )
  {
    $cage_record_in = @searchinfo[0];
    chomp($cage_record_in);             #where does that nasty lf come from?

    # Extract values from record
    ($cage_num, $room_num, $investigator,$co_investigator, $specie,
     $strain, $sex, $animal_id, $count_num, $rec_date,$apn_num,$cost_code,
     $vendor_code, $rate_level, $IEB_timestamp, 
     $ops1, $ops2, $ops3, $ops4, $ops5, $cage_type) = split(/\|/,$cage_record_in);
     chomp ($rate_level);
     chomp ($ops5);
     chomp ($cage_type);
     $blip_isa = 'cage';     # Only set blip_isa when valid cage is found.
     $cage_card = $blip;     # Remember:  cage_card displays as "Cage XXXX"
                             #            cage_num is just "XXXX"
  } # end if($chunks > 0)

}   #end sub cage_srch

#--------------------------------------#

sub census_transaction
{
   # This sub processes a census transaction.
   $blip_was = $blip_isa;
   $blip = $cage_card;
   cage_srch(); 
   $blip_isa = $blip_was;

   if ($Q2 == -1)    # Q2 will only be other than minus one on Friday (head_count day)
   {              
     $Q1 = 'N/A';    # Use 'N/A' on cage_count day.  Use actual number on head_count day.
   }

   $census_data = join("\|", $cage_num,        # GIGO
                             $room_num,        # GIGO
                             $investigator,    # GIGO
                             $co_investigator, # GIGO
                             $specie,          # GIGO
                             $strain,          # GIGO
                             $sex,             # GIGO
                             $animal_id,       # GIGO
                             $count_num,       # GIGO
                             $rec_date,        # GIGO
                             $apn_num,         # GIGO
                             $cost_code,       # GIGO
                             $vendor_code,     # GIGO
                             $rate_level,      # GIGO
                             $IEB_timestamp,   # GIGO
                             $OPS_timestamp,
                             $badge,
                             $Q1,
                             "N/A",            # This is E1 in euthanize record.
                             $room_barcode,    # room_barcode is not used with EUTH transaction.
                             $cage_prefix );   ##$cage_type ); Send actual scanned prefix, not GIGO
       # Write the transaction record
      $datafile = "scanned.txt";               # File resides in /var/www/html.
      open (FILE, ">> $datafile")  || die "Unable to write LAM Barcode Scan results file= $datafile: $!";
      print FILE "$census_data\n";
      close (FILE);

# Send the file from LAM transport server to INTERIM web server.
#$host = "131.158.7.207";
#$ftp=Net::FTP->new($host);
#$ftp->login("oritx100","gasbot") or die "could not login\n";
#$ftp->cwd("/lam");
#$ftp->ascii;
#$ftp->put("scanned.txt");
#$ftp->quit;

} # end sub census_transaction 
#--------------------------------------#

sub euthanize_transaction
{
# This sub processes a euthanize transaction

   $blip_was = $blip_isa;
   $blip = $cage_card;
   cage_srch();
   $blip_isa = $blip_was;

   $euthanize_data = join("\|", 
                             $cage_num,        # GIGO
                             $room_num,        # GIGO
                             $investigator,    # GIGO
                             $co_investigator, # GIGO
                             $specie,          # GIGO
                             $strain,          # GIGO
                             $sex,             # GIGO
                             $animal_id,       # GIGO
                             $count_num,       # GIGO
                             $rec_date,        # GIGO
                             $apn_num,         # GIGO
                             $cost_code,       # GIGO
                             $vendor_code,     # GIGO
                             $rate_level,      # GIGO
                             $IEB_timestamp,   # GIGO
                             $OPS_timestamp,
                             $EUTH_badge,
                             "N/A",           # This is Q1 in census record
                             $E1,
                             # room_barcode is not used with EUTHANIZE
                             $cage_prefix );   ###$cage_type);  Send actual scanned cage_prefix not GIGO
       # Write the transaction record
      $datafile = "scanned.txt";              # File resides in /var/www/html
      open (EUTH_FILE, ">> $datafile")  || die "Unable to write LAM Barcode Scan results file= $file: $!";
      print EUTH_FILE "$euthanize_data\n";
      close (EUTH_FILE);

# Keep a file of euthanize actions just in case awkward mishaps are scrutinized.
#      $euthfile = "animal_euthanize_history.txt";
#      open (EUTH_HISTORY, ">> $euthfile");
#      print EUTH_HISTORY "$euthanize_data\n";
#      close (EUTH_HISTORY);

# Send the file to from LAM transport server to interim web server.
#$host = "131.158.7.207";
#$ftp=Net::FTP->new($host);
#$ftp->login("oritx100","gasbot") or die "could not login\n";
#$ftp->cwd("/lam");
#$ftp->ascii;
#$ftp->put("scanned.txt");
#$ftp->quit;

  # Reset Euthanize variables occurs elsewhere after being used in confirmation display
} # end sub euthanize_transaction
#--------------------------------------#
sub html
{

# This is the HTML redisplay.  It is a static display, but gets built with dymamic values
# during the course of this application.
#
# The main information section used a display table; 3 rows with 2 columns.
# For ease of description, the table elements are named in Excel style.

# Variables in the raw HTML are:
#
# $use_javascript  (either null, $javascript_census_check or $javascript_euthanize_check
# $display_date
# $function_action 
# $row1
# $row2
# $row3
# $hidden_values
# $button_line
#
#$use_javascript


print "Content-type: text/html\n\n";
print <<EOL

<HTML>
<HEAD> 
</HEAD>
<BODY onLoad='document.scanner_form.blip.focus();'>
<FORM NAME='scanner_form' ACTION='blip.pl' METHOD='get'>
$hidden_values

<TABLE BORDER='0' CELLSPACING='0' CELLPADDING='0'>
<TR>
<TD ALIGN='Left' VALIGN='top'>
<IMG BORDER='0' HEIGHT='65' WIDTH='73' SRC='USUlogo.JPG' ALT='Uniformed Services University'>
</TD>

<TD ALIGN='center' VALIGN='center' bgcolor="lightblue" fgcolor='white'
  width='141'>LAM Scanner </TD>
</TR>
</TABLE>

<TABLE WIDTH='100%' BORDER='0' BGCOLOR='00ff20'>
<TR>
<TD ALIGN='center'><FONT FACE='arial' SIZE='-2'>
<B>Lam Information</B></FONT>
</TD>
</TR>

</TABLE>

<TABLE BORDER='0' CELLSPACING='0' CELLPADDING='0'>
<TR></TR>

<TR><TD colspan='2' align='center'> $person_scanning </TD> </TR>
</TABLE>
<HR>
<TABLE BORDER='0' CELLSPACING='0' CELLPADDING='0'>
<TR></TR>

$row1
$row2
$row3
$row4

</TABLE>
</FORM>

</BODY>
</HTML>
EOL

;
exit(0);

}  # end sub html
#------------------

