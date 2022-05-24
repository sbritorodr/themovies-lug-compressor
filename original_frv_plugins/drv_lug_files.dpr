// -------------------------------------------------------------------------- //
// Black & White, Black & White 2, Fable: The Lost Chapters .LUG support ==== //
// -------------------------------------------------------------------------- //

type LUG_Chunk = packed record
       ID: array[0..31] of char;
       Size: integer;
     end;
     LUG_LHAudioBankMetaData = packed record
       Unknown0: array[0..27] of byte;
       NumEntries: integer;
     end;
     // SampleID: Integer;
     // SampleName: get32
     LUG_LHAudioBankMetaData_Entry = packed record
       Size: Integer;
       Offset: Integer;
       Unknown1: integer;         // 01 00 01 00
       SampleRate: Integer;
       Unknown2: Integer;         // 00 00 00 00 or FF FF FF FF
       Unknown3: Integer;
     end;
     LUG_LHFileSegmentBankInfo = packed record
       TitleDescription: array[0..519] of char;
     end;
     LUG_LHAudioBankSampleTable = packed record
       NumEntries1: word;
       NumEntries2: word;         // Always identical to NumEntries1 ?
     end;
     LUG_LHAudioBankSampleTable_Entry = packed record
       SampleName: array[0..255] of char;
       Unknown1: integer;
       Unknown2a: integer;
       Unknown2b: integer;
       Size: integer;
       RelOffset: integer;        // Offset in WaveData of LHAudioWaveData bloc
       Unknown3: integer;
       Unknown4: integer;
       Unknown5: integer;
       Unknown6: integer;
       Unknown7: integer;
       SampleRate: integer;
       Unknown8: integer;
       Unknown9: integer;
       Unknown10: integer;
       Unknown11: integer;
       Unknown12: integer;
       SampleDescription: array[0..255] of char;
       Unknown13: array[0..75] of byte;
     end;

function ReadLionheadAudioBank(src: string): Integer;
var HDR: LUG_Chunk;
    ABST_HDR: LUG_LHAudioBankSampleTable;
    ABST_ENT: LUG_LHAudioBankSampleTable_Entry;
    ABST_ENT_Size, DirSize, DirNum: cardinal;
    IDst: array[0..7] of char;
    disp: string;
    NumE, x: integer;
    DataOffset, DirOffset, FLength, CurP, idx: integer;
    MusicOffset, MusicSize, OldPer, Per: integer;
    tagid, nam: string;
    IsMusic, IsFirst: boolean;
    StoredOffsets: TIntList;
begin

  Fhandle := FileOpen(src, fmOpenRead or fmShareDenyWrite);

  if FHandle > 0 then
  begin

    // We seek to start of file and read the 8 first bytes
    FileSeek(Fhandle, 0, 0);
    FileRead(FHandle, IDst, 8);

    // Lionhead Audio Banks starts with "LiOnHeAd"
    if (IDst <> 'LiOnHeAd') then
    begin
      FileClose(Fhandle);
      FHandle := 0;
      Result := -3;
      ErrInfo.Format := 'LUG';
      ErrInfo.Games := 'Black & White, Black & White 2, Fable: The Lost Chapters, ..';
    end
    else
    begin

      // We initialize all variables
      DataOffset := 0;
      DirOffset := 0;
      DirSize := 0;
      DirNum := 0;

      // We retrieve the file size
      FLength := FileSeek(FHandle,0,2);
      // We seek to the first chunk
      FileSeek(FHandle,8,0);

      // We go through all chunks of data in the sound bank
      repeat

        FileRead(FHandle,HDR,SizeOf(HDR));

        // Current offset
        CurP := FileSeek(FHandle,0,1);

        // Chunk ID
        tagid := strip0(HDR.ID);

        // If we reached the sound data chunk we store the data offset
        if (tagid = 'LHAudioWaveData') then
        begin
          DataOffset := CurP;
        end
        // If we reached the sample table chunk
        else if (tagid = 'LHAudioBankSampleTable') then
        begin
          // Read the chunk header
          FileRead(FHandle,ABST_HDR,SizeOf(ABST_HDR));
          // We get the number of entries
          DirNum := ABST_HDR.NumEntries1;
          // Directory offset is current offset (therefore chunk data offset + 4)
          DirOffset := CurP + 4;
          // Directory size is chunk data - 4 (chunk header size)
          DirSize := HDR.Size - 4;
        end;

        // We go to next chunk
        FileSeek(FHandle,CurP + HDR.Size,0);

      until ((length(tagid) = 0) or (FileSeek(FHandle,0,1) >= FLength)) ;

      // If the 2 blocs we are using to read the sound bank don't exist then just exit
      //   LHAudioBankSampleTable   --> Directory
      //   LHAudioWaveData          --> Sound Data
      // We also checks if the integers have positive values
      if (DirOffset <= 0) or (DataOffset <= 0) or (DirSize <= 0) then
      begin
        FileClose(Fhandle);
        FHandle := 0;
        Result := -3;
        ErrInfo.Format := 'LUG';
        ErrInfo.Games := 'Black & White, Black & White 2, Fable: The Lost Chapters, ..';
      end
      else
      begin

        // Calculates the entry size
        ABST_ENT_Size := DirSize div DirNum;
        // I know at least those two values:
        //   640 for Black & White .SAD files
        //   652 for Black & White 2 and Fable: The Lost Chapters .LUG files
        // If the value is under 652, no problem we should be able to handle it
        // if not this will do a write access violation I think, so we better exit if it happen

        // Entry size must fill the sound bank table, if not something is wrong so we exit
        if (ABST_ENT_Size <= 652) and ((DirSize mod ABST_ENT_Size) <> 0) then
        begin
          FileClose(Fhandle);
          FHandle := 0;
          Result := -3;
          ErrInfo.Format := 'LUG';
          ErrInfo.Games := 'Black & White, Black & White 2, Fable: The Lost Chapters, ..';
        end
        else
        begin

          // We initialize the number of entries to 0
          NumE := 0;

          // We go to the directory offset
          FileSeek(FHandle,DirOffset,0);

          // We initialize music related variables
          MusicOffset := 0;
          MusicSize := 0;
          IsMusic := True;
          IsFirst := True;

          // Percentage of completion display
          OldPer := 0;

          // We will store offsets to be sure there is no duplicate entries
          StoredOffsets := TIntList.Create;

          try

            // For each entry in the directory
            for x:= 1 to DirNum do
            begin

              // Display percentage of completion
              Per := Round((x / DirNum)*100);
              if (Per >= OldPer + 5) then
              begin
                SetPercent(Per);
                OldPer := Per;
              end;

              // We read the entry
              FileRead(FHandle,ABST_ENT,ABST_ENT_Size);

              // We retrieve the sample name (filename) by stripping null chars at the end
              disp := strip0(ABST_ENT.SampleName);

              // If the filename is a full Windows path (which is always the case)
              //   i.e: C:\Temp\Toto.wav
              // Then we strip the 3 first chars
              //   i.e: Temp\Toto.wav
              if copy(disp,2,2) = ':\' then
                Disp := Copy(disp,4,length(disp)-3);

              // We extract the filename from the path
              //   i.e: Toto.wav
              nam := ExtractFileName(disp);

              // If size of entry is not zero
              if ABST_ENT.Size > 0 then
              begin
                // If this is the first time we see that offset
                if not(StoredOffsets.Find(ABST_ENT.RelOffset,idx)) then
                begin
                  // We store it
                  StoredOffsets.Add(ABST_ENT.RelOffset);

                  // We check if we are in a music audio bank
                  // filenames (without path) start with sect and end with .mpg
                  // Each sector of the video is therefore stored as different file (sometimes more than 400 files for a song..)
                  // so we basically join them as one file
                  IsMusic := IsMusic and (length(nam) >= 4) and (lowercase(Copy(nam,1,4)) = 'sect') and (lowercase(extractfileext(nam)) = '.mpg');
                  if IsMusic then
                  begin
                    // If this is the first entry
                    if IsFirst then
                    begin
                      // We store the offset of the music file (which should be DataOffset + 0 actually)
                      MusicOffset := ABST_ENT.RelOffset;
                      // We set IsFirst to false
                      IsFirst := Not(IsFirst);
                    end;
                    // We increase the size of the music file with the size of entry
                    Inc(MusicSize,ABST_ENT.Size);
                  end
                  // If this is not a music audio bank (used by Black & White .SAD files)
                  else
                  begin
                    // We store the entry path & name
                    // Offset is Data Offset + Relative Offset of the entry
                    FSE_Add(disp,ABST_ENT.RelOffset+DataOffset,ABST_ENT.Size,0,0);

                    // We increase by 1 the number of available entries
                    Inc(NumE);
                  end;
                end;
              end;
            end;
          finally // Finally we free the stored offsets because we don't need them anymore
            FreeAndNil(StoredOffsets);
          end;

          // If we detected a music audio bank
          If IsMusic then
          begin
            // We extract the currently opened filename
            // and we put '.mpg' as extension
            nam := ExtractFilename(src);
            nam := ChangeFileext(nam,'.mpg');
            // We store a unique entry with MusicOffset + DataOffset offset
            // and MusicSize size (sum of all single entries)
            FSE_Add(nam,MusicOffset+DataOffset,MusicSize,0,0);
            NumE := 1;
          end;

          // Final steps, we return the number of entries found
          Result := NumE;

          // Send identification
          DrvInfo.ID := 'LHAB';    // Lionhead Audio Bank
          // Directories are using '\' as separators
          DrvInfo.Sch := '\';
          DrvInfo.FileHandle := FHandle;
          // Entries are not compressed, nor crypted, extraction will be handled by Dragon UnPACKer (core) directly
          DrvInfo.ExtractInternal := False;

        end;
      end;
    end;
  end
  else
    Result := -2;

end;
