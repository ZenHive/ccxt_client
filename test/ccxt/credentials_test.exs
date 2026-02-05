defmodule CCXT.CredentialsTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials

  describe "new/1" do
    test "creates credentials with required fields" do
      assert {:ok, creds} = Credentials.new(api_key: "key", secret: "secret")
      assert creds.api_key == "key"
      assert creds.secret == "secret"
      assert creds.password == nil
      assert creds.sandbox == false
    end

    test "creates credentials with all fields" do
      assert {:ok, creds} =
               Credentials.new(
                 api_key: "key",
                 secret: "secret",
                 password: "pass",
                 sandbox: true
               )

      assert creds.api_key == "key"
      assert creds.secret == "secret"
      assert creds.password == "pass"
      assert creds.sandbox == true
    end

    test "returns error when api_key is missing" do
      assert {:error, :missing_api_key} = Credentials.new(secret: "secret")
    end

    test "returns error when secret is missing" do
      assert {:error, :missing_secret} = Credentials.new(api_key: "key")
    end

    test "returns error when both are missing" do
      assert {:error, :missing_api_key} = Credentials.new([])
    end
  end

  describe "new!/1" do
    test "creates credentials with required fields" do
      creds = Credentials.new!(api_key: "key", secret: "secret")
      assert creds.api_key == "key"
      assert creds.secret == "secret"
    end

    test "raises when api_key is missing" do
      assert_raise ArgumentError, "api_key is required", fn ->
        Credentials.new!(secret: "secret")
      end
    end

    test "raises when secret is missing" do
      assert_raise ArgumentError, "secret is required", fn ->
        Credentials.new!(api_key: "key")
      end
    end
  end

  describe "struct" do
    test "can be created directly with required keys" do
      creds = %Credentials{api_key: "key", secret: "secret"}
      assert creds.api_key == "key"
      assert creds.sandbox == false
    end

    test "raises when required keys are missing" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(Credentials, password: "pass")
      end
    end
  end
end
