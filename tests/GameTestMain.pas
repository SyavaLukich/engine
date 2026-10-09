{ GameTestMain - запуск проверок игры: ./build/tests/test_game (код возврата 0 = все проверки пройдены). }
program GameTestMain;

{$mode objfpc}{$H+}

uses
  TestKit, TestGame;

begin
  GPassed := 0;
  GFailed := 0;
  RunGameTests;
  WriteLn('passed: ', GPassed, ', failed: ', GFailed);
  if GFailed > 0 then
    Halt(1);
end.
