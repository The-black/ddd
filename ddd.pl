#!/usr/bin/perl -w
#####################################################################################
#
# ddd.pl - A perl wrapper for dd, to be used for Defective Disk Duplication
#
# By Nadav Pe'er (nadav@peer.org.il)
#
#  
#
# (c) All rights reserved.
#
#
#


######################################################################################
#
# Includes and global definitions
#
#

use strict 'vars' ;
use POSIX ;

use vars qw($version $versionDate $usage $logFile $mapFile) ;
use vars qw($inFile $outFile $blockSize $defectiveBlockSize $retryFaultyBlock $seekBlocks $skipBlocks $globalCount) ;
use vars qw($remaining $retryCounter $blockFactor) ;
use vars qw($bigBlock @bigBlockOffset @bigBlockSize) ; 				# Initial defect map
use vars qw($defectiveBlock @defectiveBlockOffset @defectiveBlockSize);		# Detailed defect map
use vars qw($defectiveBlock2 @defectiveBlockOffset2 @defectiveBlockSize2); 	# Temporary defect map




######################################################################################
#
# Configuration
#
#

$version = 0.2 ;		# Script Version
$versionDate = "June 29, 2013";	# Script Date
$inFile = "" ;			# Initialize
$outFile = "" ;			# Initialize 
$blockSize = 512 ;		# Default block size in KB, unless otherwise specified on the command-line
$defectiveBlockSize = 1 ;	# Block size in KB when retrying a faulty section
$retryFaultyBlock = 2 ;		# Number of retries for each faulty block 
$seekBlocks = 0 ;		# Number of blocks to skip on the output
$skipBlocks = 0 ;		# Number of blocks to skip on the input
$globalCount = 0 ;		# Minimum number of blocks to copy, 0 means untill the end
$logFile = "./ddd.log";		# Log file name
$mapFile = "./ddd.map";		# Map file name

$blockFactor = int($blockSize / $defectiveBlockSize) ;
if (($blockFactor * $defectiveBlockSize) < $blockSize) {
	die "Wrong Configuration: Block Size must be a multiple of $defectiveBlockSize \n" ;
}; # of if


#####
# Initialize user parameters from the command line
# Open log file
#####
sub initialize() {
	$retryCounter = 0 ;
	print "ddd.pl v$version ($versionDate), by Nadav Pe'er (nadav\@peer.org.il) \n\n" ;

	$usage = "Usage: ddd.pl if=xxx of=xxx [bs=nnnK] [seek=nnn] [skip=nnn]\n\n" ;
	$usage .= "Where:\n" ;
	$usage .= "if = Source Device to copy (Input File)\n" ;
	$usage .= "of = Destination Device/File (Output File)\n" ;
	$usage .= "bs = Default Block Size (in KB, use K multiplier only, for example: bs=64K) \n" ;
	$usage .= "seek = Blocks to skip on output\n" ;
	$usage .= "skip = Blocks to skip on input\n" ;
	$usage .= "count = Minimum number of blocks to copy\n\n" ;
	if ($#ARGV == -1) {
		print $usage ;
		exit 1 ;
	} else {
#		print "Arguments:\n" ;
		for my $i (0 .. $#ARGV) {
#			print "$ARGV[$i]\n" ;

			if ($ARGV[$i] =~ /^if\=/) {
				$inFile = $' ;
#				print "Input File = $inFile\n" ;
			} ; # of if			

			if ($ARGV[$i] =~ /^of\=/) {
				$outFile = $' ;
#				print "Output File = $outFile\n" ;
			} ; # of if			


			if ($ARGV[$i] =~ /^bs\=/) {
				$blockSize = $' ;
				
				if ($blockSize =~ /K$/) {
					$blockSize = $` ;
					$blockFactor = int($blockSize / $defectiveBlockSize) ;
					if (($blockFactor * $defectiveBlockSize) < $blockSize) {
						die "Block Size must be a multiple of $defectiveBlockSize \n" ;
					}; # of if

				} else {
					die "Block Size must be in KB, for example: bs=64K\n" ;
				} ; # of if
				

				
#				print "Block Size = $blockSize\KB\n" ;
			} ; # of if			

			if ($ARGV[$i] =~ /^skip\=/) {
				$skipBlocks = $' ;
				if ($skipBlocks =~ /^\d+$/) {
#					print "Skip Blocks (input) = $skipBlocks\n" ;
				} else {
					print "Invalid skip value, quitting.\n" ;
					exit 1 ;	
				} ; # of if	
			} ; # of if			

			if ($ARGV[$i] =~ /^seek\=/) {
				$seekBlocks = $' ;
				if ($seekBlocks =~ /^\d+$/) {
#					print "Seek Blocks (output) = $seekBlocks\n" ;
				} else {
					print "Invalid seek value, quitting.\n" ;
					exit 1 ;	
				} ; # of if	
			} ; # of if			

                        if ($ARGV[$i] =~ /^count\=/) {
                                $globalCount = $' ;
                                if ($globalCount =~ /^\d+$/) {
#                                       print "Count Blocks = $globalCount\n" ;
                                } else {
                                        print "Invalid count value, quitting.\n" ;
                                        exit 1 ;
                                } ; # of if
                        } ; # of if
                                                                                                                             


		} ; # of for
		
		if ($inFile eq "") {
			print "Missing Input File\n" ;
		} ; # of if	

		if ($outFile eq "") {
			print "Missing Output File\n" ;
		} ; # of if	

		if (($outFile eq "") or ($inFile eq "")) {
			print "\n$usage" ;
			exit 1 ;
		} ; # of if	

		
		print "Copy Parameters:\n\n" ;
		print "Input File = $inFile\n" ;
		print "Output File = $outFile\n" ;
		print "Block Size = $blockSize KB\n" ;
		print "Skip Blocks (input) = $skipBlocks\n" ;
		print "Seek Blocks (output) = $seekBlocks\n" ;
		print "Minimum number of Blocks = $globalCount\n\n\n" ;

		open (LOGFILE, "> $logFile") or die "cannot open log file $logFile: $!" ;		

		print LOGFILE "Copy Parameters:\n\n" ;
		print LOGFILE "Input File = $inFile\n" ;
		print LOGFILE "Output File = $outFile\n" ;
		print LOGFILE "Block Size = $blockSize KB\n" ;
		print LOGFILE "Skip Blocks (input) = $skipBlocks\n" ;
		print LOGFILE "Seek Blocks (output) = $seekBlocks\n" ;
		print LOGFILE "Minimum number of Blocks = $globalCount\n\n\n" ;

		close LOGFILE ;


		open (MAPFILE, "> $mapFile") or die "cannot open log file $logFile: $!" ;		
		print MAPFILE "ddd Initialized\n\n" ;
		close MAPFILE ;



	} ; # of if
	
	
}; # of sub initParams

#####
# Write a single log entry
#####
sub logWrite{
	my $entry = shift() ;
	chomp $entry ;
	my $currentTime = time();
	my ($tmpSec, $tmpMin, $hour, $dom, $mon, $year, $wday, $yday, $isdst) = localtime($currentTime) ;
	my $min = ($tmpMin > 9)? $tmpMin:"0".$tmpMin ;
	my $sec = ($tmpSec > 9)? $tmpSec:"0".$tmpSec ;
	$year += 1900 ;
	$mon += 1 ;
	open (LOGFILE, ">> $logFile") or die "cannot open log file $logFile: $!" ;		
	print LOGFILE $dom."/".$mon."/".$year." ".$hour.":".$min.":".$sec."   ".$entry."\n" ;
	close LOGFILE ;
}; # of sub logWrite



#####
# Copy a single file
#####
sub copyFile{
	my $sourceFile = shift() ;
	my $destFile .= shift() ;
	open (SOURCE, $sourceFile) or die "copyFile: cannot open source file $sourceFile: $!" ;		
	open (DEST, "> $destFile") or die "copyFile: cannot open destination file $destFile: $!" ;		

	while (<SOURCE>) {
		print DEST $_ ;
	}	
	close SOURCE ;
	close DEST ;
}; # of sub logWrite




#####
# Copy a defined section using the dd command
#####
sub dodd(@){
	my ($seek, $skip, $bs, $count, $retry) = @_ ;
	my $gotError ;
	my $recordsIn ;
	my $recordsOut ;
	my $result ;
	
	my $cmd = "dd if=$inFile of=$outFile bs=$bs"."K count=$count seek=$seek skip=$skip conv=notrunc 2\>\&1 |" ;
#	print "Command is: $cmd\n" ;

	while ($retry >= 0) {
		$gotError = 0 ;
		open (DD, $cmd) or die "cannot use dd: $!" ;
		$result = <DD> ;
#		print "Result is: $result \n" ;

		chomp $result ;
		
		if ($result =~ /^dd:/) {		# Check for error
			$gotError = 1 ;
			$result = <DD> ;
		} ; # of if
			
		if ($result =~ /\+\d+ records in/) {	# Valid records in
			$recordsIn = $` ;
		} else {
			die "Incorrect syntax for records in" ;
		} ; # of if
	
		$result = <DD> ;
		close DD ;	
	
		if ($result =~ /\+\d+ records out/) {	# Valid records out
			$recordsOut = $` ;
		} else {
			die "Incorrect syntax for records out" ;
		} ; # of if
	
		die "Incorrect number of blocks written - probably a problem in the output device" unless ($recordsOut == $recordsIn) ;
		die "Error reported although all records were read and written" unless (($gotError == 0) or ($recordsOut < $count)) ;
#		print "Total Records copied: $recordsOut \n" ;		
		return $recordsOut, $gotError unless (($recordsOut == 0) and ($gotError == 1));
		$retry-- ;		
		
	} ; # of while
	return 0,1 ;
}; # of sub dodd	


#####
# Copy entire requested range with original block size
#####
sub massCopy(){
	print "Phase 1: Copying good sections and mapping faulty ones\n" ;
	logWrite "Phase 1: Copying good sections and mapping faulty ones" ;
	my $status = 1 ;	# OK Flag: 0=OK, 1=Error
	my $recordsOK = 0 ;	# Records successfully copied
	my $currRecord = 0 ;	# Current Position in blocks
	my $currPosition = 0 ;	# Current Position in KB
	my $totalBadBlocks = 0 ;# Total bad blocks in KB
	my $totalChains	= 0 ;	# Total number of bad chains
	my $displayInterval = ceil(1024 / $blockSize) ;
	$bigBlock = 0 ;		# Index of fault block arrays
	$bigBlockOffset[0] = 0 ;
	$bigBlockSize[0] = 0 ;
	
	while ($status) {
		($recordsOK, $status) = dodd ($currRecord + $seekBlocks, $currRecord + $skipBlocks, $blockSize, $displayInterval, 0)  ;
		$currRecord += $recordsOK ;

                if (($currRecord < $globalCount) && ($globalCount > 0)) { # Not finished yet according to count
                         $status = 1 ;
                } ;
                                                                                                                             
		if ($status) {	# Error encountered
			if ($recordsOK) {	# Records returned
				$bigBlock++ unless (($bigBlock == 0) and ($bigBlockSize[0] == 0)) ; 	# Create new record
				$bigBlockOffset[$bigBlock] = $currRecord ;
				$bigBlockSize[$bigBlock] = 1 ;			
			} else {
				$bigBlockSize[$bigBlock]++ ;
			} ; # of if			
			$totalBadBlocks += $blockSize  ;
			$currRecord ++ ;
		} else {
			if ($recordsOK == $displayInterval) { # Not finished yet ...
				$status = 1 ;
			} ;	

} ;
		$currPosition = $currRecord * $blockSize / 1024 ;
		$totalChains = $bigBlock + 1 ;
		print "$currPosition MB Copied in $totalChains section(s), $totalBadBlocks KB bad                      \r" ;
		logWrite "$currPosition MB Copied in $totalChains section(s), $totalBadBlocks KB bad" ;
	} ; # of while
	print "\n\n" ;	
	logWrite "\n\n" ;
	return $totalBadBlocks ;
}; # of sub massCopy	

#####
# Copy faulty blocks from massCopy with faulty block size, create initial faulty blocks map
#####
sub mapFaultyBlocks(){
	print "Phase 2: Remapping faulty sections\n" ;
	logWrite "Phase 2: Remapping faulty sections" ;
	my $tmpChains ;
	$defectiveBlock = 0 ;		# Index of fault block arrays
	my $totalBadBlocks = 0 ;# Total bad blocks in KB
	my $segmentsRemaining = $bigBlock + 1;	# Current Position in KB
	print "$segmentsRemaining segment(s) remaining, $totalBadBlocks KB bad                   \r" ;
	logWrite "$segmentsRemaining segment(s) remaining, $totalBadBlocks KB bad" ;
	for my $index (0 .. $bigBlock) {
		my $status = 1 ;	# OK Flag: 0=OK, 1=Error
		my $recordsOK = 0 ;	# Records successfully copied
		my $currRecord = 0 ;	# Current Position in blocks
		$defectiveBlockOffset[$defectiveBlock] = $bigBlockOffset[$index] * $blockFactor ;
		$defectiveBlockSize[$defectiveBlock] = 0 ;

		while ($currRecord < ($bigBlockSize[$index] * $blockFactor)) {
			($recordsOK, $status) = dodd (($currRecord + ($seekBlocks + $bigBlockOffset[$index]) * $blockFactor), ($currRecord + ($skipBlocks + $bigBlockOffset[$index]) * $blockFactor), $defectiveBlockSize, $bigBlockSize[$index] * $blockFactor, 0)  ;
			$currRecord += $recordsOK ;
			if ($status) {	# Error encountered
				if ($recordsOK) {	# Records returned
					$defectiveBlock++ unless ($defectiveBlockSize[$defectiveBlock] == 0) ; 	# Create new record
					$defectiveBlockOffset[$defectiveBlock] = $currRecord + ($bigBlockOffset[$index] * $blockFactor) ;
					$defectiveBlockSize[$defectiveBlock] = 1 ;			
				} else {
					$defectiveBlockSize[$defectiveBlock]++ ;
				} ; # of if			
				$totalBadBlocks += $defectiveBlockSize  ;
				$currRecord ++ ;
			} ;	
			$tmpChains = $defectiveBlock + 1;
			print "$segmentsRemaining segment(s) remaining, $totalBadBlocks KB bad in $tmpChains chain(s)              \r" ;
			logWrite "$segmentsRemaining segment(s) remaining, $totalBadBlocks KB bad in $tmpChains chain(s)" ;
		} ; # of while
		$segmentsRemaining-- ;
		$defectiveBlock++ ;
		print "$segmentsRemaining segment(s) remaining, $totalBadBlocks KB bad in $defectiveBlock chain(s)                \r" ;
		logWrite "$segmentsRemaining segment(s) remaining, $totalBadBlocks KB bad in $defectiveBlock chain(s)" ;
	} ; # of for	
	print "\n\n" ;
	logWrite "\n\n" ;
	return $totalBadBlocks ;
}; # of sub mapFaultyBlocks


#####
# Clear faulty blocks on output
#####
sub clearFaultyBlocks(){
	print "Phase 3: clearing faulty sections on output\n\n" ;
	logWrite "Phase 3: clearing faulty sections on output\n\n" ;
	my $tmpInputFile = $inFile ;	# keep original infile value
	$inFile = '/dev/zero' ;		# use /dev/zero to clear
	my $status = 1 ;	# OK Flag: 0=OK, 1=Error
	my $recordsOK = 0 ;	# Records successfully copied
	$defectiveBlock-- ;
	for my $index (0 .. $defectiveBlock) {
#		print "Index = $index, offset = $defectiveBlockOffset[$index] , seek = $seekBlocks , factor = $blockFactor , skip = $skipBlocks , bs = $defectiveBlockSize , count = $defectiveBlockSize[$index] \n" ;
		($recordsOK, $status) = dodd ($defectiveBlockOffset[$index] + ($seekBlocks * $blockFactor), $defectiveBlockOffset[$index] + ($skipBlocks * $blockFactor), $defectiveBlockSize, $defectiveBlockSize[$index] , 0)  ;
		if ($status) {	# Error encountered
			die "Error on output device, quitting. ($!)\n" ;
		} ;	
	} ; # of for	
	$inFile = $tmpInputFile ;	# Restore original input file
}; # of sub clearFaultBlocks 	





#####
# Copy remaining faulty blocks map
#####
sub copyMap(){
	copyFile($mapFile, $mapFile.".bak") ;

	open (MAPFILE, "> $mapFile") or die "cannot open log file $logFile: $!" ;		
	print MAPFILE "Faulty Block Map, offset:size records\n" ;



#	print "Defective Block Map:\n" ;
	$defectiveBlock = $defectiveBlock2 ;
	for my $index (0 .. $defectiveBlock) {
#		print "Offset: $defectiveBlockOffset[$index] \-\> $defectiveBlockOffset2[$index], Size: $defectiveBlockSize[$index] \-\> $defectiveBlockSize2[$index] \n" ;
		$defectiveBlockOffset[$index] = $defectiveBlockOffset2[$index] ;
		$defectiveBlockSize[$index] = $defectiveBlockSize2[$index] ;
		print MAPFILE $defectiveBlockOffset[$index].":".$defectiveBlockSize[$index]."\n" ;
	} ; # of for	

	close MAPFILE ;

}; # of copyMap	





#####
# Copy remaining faulty blocks, update faulty blocks map
#####
sub retryFaultyBlocks(){
	my $status = 1 ;	# OK Flag: 0=OK, 1=Error
	my $recordsOK = 0 ;	# Records successfully copied
	my $totalBadBlocks = 0 ;
	my $tmpChains = 0 ;
	my $tmpRemainingChains = $defectiveBlock ;
	$defectiveBlock2 = 0 ;
	$defectiveBlockOffset2[0] = 0 ;
	$defectiveBlockSize2[0] = 0 ;	
	for my $index (0 .. $defectiveBlock) {
		my $currRecord = 0 ;	# Current Position in blocks
		$defectiveBlockOffset2[$defectiveBlock2] = $defectiveBlockOffset[$index] ;
		$defectiveBlockSize2[$defectiveBlock2] = 0 ;
#		print "Index = $index, offset = $defectiveBlockOffset[$index] , seek = $seekBlocks , factor = $blockFactor , skip = $skipBlocks , bs = $defectiveBlockSize , count = $defectiveBlockSize[$index] \n" ;

		while ($currRecord < $defectiveBlockSize[$index]) {
			($recordsOK, $status) = dodd ($defectiveBlockOffset[$index] + ($seekBlocks * $blockFactor), $defectiveBlockOffset[$index] + ($skipBlocks * $blockFactor), $defectiveBlockSize, $defectiveBlockSize[$index] , $retryFaultyBlock)  ;
			$currRecord += $recordsOK ;
			if ($status) {	# Error encountered
				if ($recordsOK) {	# Records returned
					$defectiveBlock2++ unless ($defectiveBlockSize2[$defectiveBlock2] == 0) ; 	# Create new record
					$defectiveBlockOffset2[$defectiveBlock2] = $currRecord + $defectiveBlockOffset[$index]  ;
					$defectiveBlockSize2[$defectiveBlock2] = 1 ;			
				} else {
					$defectiveBlockSize2[$defectiveBlock2]++ ;
				} ; # of if			
				$totalBadBlocks += $defectiveBlockSize  ;
				$currRecord ++ ;
			} ;	
			$tmpChains = $defectiveBlock2 + 1;
			print "$totalBadBlocks KB bad in $tmpChains chain(s) ($tmpRemainingChains chain(s) remaining)             \r" ;
			logWrite "$totalBadBlocks KB bad in $tmpChains chain(s) ($tmpRemainingChains chain(s) remaining)" ;
		} ; # of while
		$defectiveBlock2++ if $defectiveBlockSize2[$defectiveBlock2] ;
		$tmpRemainingChains-- ;

	} ; # of for	
	print "$totalBadBlocks KB bad in $defectiveBlock2 chain(s)                                                    \n" ;
	logWrite "$totalBadBlocks KB bad in $defectiveBlock2 chain(s)" ;
	$defectiveBlock2 -- ;
	
	copyMap ;
	return $totalBadBlocks ;
	
}; # of sub retryFaultyBlocks 		



sub success() {
	print "\n\n\n###################################\n" ;
	print "Copy completed successfully !!!  :)\n" ;
	print "###################################\n\n" ;
	exit 0 ;
} ; # of sub success	

######################################################################################
#
# Main
#
#

initialize() ;	
$remaining = massCopy() ;
success() unless $remaining ;
$remaining = mapFaultyBlocks() ;
success() unless $remaining ;
clearFaultyBlocks() ;
print "Phase 4: Retrying faulty sections\n" ;
logWrite "Phase 4: Retrying faulty sections" ;
while ($remaining) {
	$remaining = retryFaultyBlocks() ;
} ; 
exit 0 ;

	
