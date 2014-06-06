#!/usr/bin/env escript
%% -*- erlang -*-
% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-define(etap_match(Got, Expected, Desc),
        etap:fun_is(fun(XXXXXX) ->
            case XXXXXX of Expected -> true; _ -> false end
        end, Got, Desc)).

filename() -> test_util:build_file("t/temp.010").
filename1() -> test_util:build_file("t/temp.011").

main(_) ->
    test_util:init_code_path(),
    etap:plan(23),
    case (catch test()) of
        ok ->
            etap:end_tests();
        Other ->
            etap:diag(io_lib:format("Test died abnormally: ~p", [Other])),
            etap:bail()
    end,
    ok.

test() ->
    etap:is(cowdb_file:open("not a real file"), {error, enoent},
        "Opening a non-existant file should return an enoent error."),

    etap:fun_is(
        fun({ok, _}) -> true; (_) -> false end,
        cowdb_file:open(filename() ++ ".1", [create, invalid_option]),
        "Invalid flags to open are ignored."
    ),

    {ok, Fd} = cowdb_file:open(filename() ++ ".0", [create, overwrite]),
    etap:ok(is_pid(Fd),
        "Returned file descriptor is a Pid"),

    etap:is({ok, 0}, cowdb_file:bytes(Fd),
        "Newly created files have 0 bytes."),

    ?etap_match(cowdb_file:append_term(Fd, foo), {ok, 0, _},
        "Appending a term returns the previous end of file position."),

    {ok, Size} = cowdb_file:bytes(Fd),
    etap:is_greater(Size, 0,
        "Writing a term increased the file size."),

    ?etap_match(cowdb_file:append_binary(Fd, <<"fancy!">>), {ok, Size, _},
        "Appending a binary returns the current file size."),

    etap:is({ok, foo}, cowdb_file:pread_term(Fd, 0),
        "Reading the first term returns what we wrote: foo"),

    etap:is({ok, <<"fancy!">>}, cowdb_file:pread_binary(Fd, Size),
        "Reading back the binary returns what we wrote: <<\"fancy\">>."),

    etap:is({ok, cowdb_compress:compress(foo, snappy)},
        cowdb_file:pread_binary(Fd, 0),
        "Reading a binary at a term position returns the term as binary."
    ),

    {ok, BinPos, _} = cowdb_file:append_binary(Fd, <<131,100,0,3,102,111,111>>),
    etap:is({ok, foo}, cowdb_file:pread_term(Fd, BinPos),
        "Reading a term from a written binary term representation succeeds."),

    BigBin = list_to_binary(lists:duplicate(100000, 0)),
    {ok, BigBinPos, _} = cowdb_file:append_binary(Fd, BigBin),
    etap:is({ok, BigBin}, cowdb_file:pread_binary(Fd, BigBinPos),
        "Reading a large term from a written representation succeeds."),

    {ok, HeaderPos} = cowdb_file:write_header(Fd, hello),
    etap:is(cowdb_file:read_header(Fd), {ok, hello, HeaderPos},
        "Reading a header succeeds."),

    {ok, BigBinPos2, _} = cowdb_file:append_binary(Fd, BigBin),
    etap:is({ok, BigBin}, cowdb_file:pread_binary(Fd, BigBinPos2),
        "Reading a large term from a written representation succeeds 2."),

    % append_binary == append_iolist?
    % Possible bug in pread_iolist or iolist() -> append_binary
    {ok, IOLPos, _} = cowdb_file:append_binary(Fd, ["foo", $m, <<"bam">>]),
    {ok, IoList} = cowdb_file:pread_iolist(Fd, IOLPos),
    etap:is(<<"foombam">>, iolist_to_binary(IoList),
        "Reading an results in a binary form of the written iolist()"),

    % XXX: How does on test fsync?
    etap:is(ok, cowdb_file:sync(Fd),
        "Syncing does not cause an error."),

    etap:is(ok, cowdb_file:truncate(Fd, Size),
        "Truncating a file succeeds."),

    %etap:is(eof, (catch cowdb_file:pread_binary(Fd, Size)),
    %    "Reading data that was truncated fails.")
    etap:skip(fun() -> ok end,
        "No idea how to test reading beyond EOF"),

    etap:is({ok, foo}, cowdb_file:pread_term(Fd, 0),
        "Truncating does not affect data located before the truncation mark."),

    etap:is(ok, cowdb_file:close(Fd),
        "Files close properly."),


    {ok, Fd2} = cowdb_file:open(filename1() ++ ".0", [create_if_missing]),
    etap:ok(is_pid(Fd2),
        "Returned file descriptor is a Pid"),

    etap:is(ok, cowdb_file:close(Fd2), "File2 closed properly."),

    {ok, Fd3} = cowdb_file:open(filename1() ++ ".0", [create_if_missing]),
    etap:ok(is_pid(Fd3),
        "Returned file descriptor is a Pid"),

    etap:is(ok, cowdb_file:close(Fd3), "File3 closed properly."),


    ok.
