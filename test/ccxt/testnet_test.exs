defmodule CCXT.TestnetTest do
  use ExUnit.Case, async: false

  # Each test clears the registry to ensure isolation, then restores original state
  setup do
    # Save current state (credentials registered in test_helper.exs)
    original_state = Agent.get(CCXT.Testnet, & &1)

    # Clear for isolated test
    CCXT.Testnet.clear()

    # Restore original state after test completes
    on_exit(fn ->
      Agent.update(CCXT.Testnet, fn _ -> original_state end)
    end)

    :ok
  end

  describe "register/2" do
    test "stores valid credentials and returns :ok" do
      assert :ok = CCXT.Testnet.register(:bybit, api_key: "key", secret: "secret", sandbox: true)

      creds = CCXT.Testnet.creds(:bybit)
      assert creds.api_key == "key"
      assert creds.secret == "secret"
      assert creds.sandbox == true
    end

    test "stores credentials with password and returns :ok" do
      assert :ok =
               CCXT.Testnet.register(:okx,
                 api_key: "key",
                 secret: "secret",
                 password: "passphrase",
                 sandbox: true
               )

      creds = CCXT.Testnet.creds(:okx)
      assert creds.api_key == "key"
      assert creds.secret == "secret"
      assert creds.password == "passphrase"
      assert creds.sandbox == true
    end

    test "returns :skipped for incomplete credentials - missing api_key" do
      assert :skipped = CCXT.Testnet.register(:bybit, secret: "secret")
      assert CCXT.Testnet.creds(:bybit) == nil
    end

    test "returns :skipped for incomplete credentials - missing secret" do
      assert :skipped = CCXT.Testnet.register(:bybit, api_key: "key")
      assert CCXT.Testnet.creds(:bybit) == nil
    end
  end

  describe "register_from_env/2" do
    test "registers when env vars present" do
      System.put_env("TEST_EXCHANGE_TESTNET_API_KEY", "key123")
      System.put_env("TEST_EXCHANGE_TESTNET_API_SECRET", "secret456")

      on_exit(fn ->
        System.delete_env("TEST_EXCHANGE_TESTNET_API_KEY")
        System.delete_env("TEST_EXCHANGE_TESTNET_API_SECRET")
      end)

      assert :ok = CCXT.Testnet.register_from_env(:test_exchange, testnet: true)

      creds = CCXT.Testnet.creds(:test_exchange)
      assert creds.api_key == "key123"
      assert creds.secret == "secret456"
      assert creds.sandbox == true
    end

    test "registers with passphrase when passphrase option is true" do
      System.put_env("TEST_EXCHANGE_API_KEY", "key123")
      System.put_env("TEST_EXCHANGE_API_SECRET", "secret456")
      System.put_env("TEST_EXCHANGE_PASSPHRASE", "mypass")

      on_exit(fn ->
        System.delete_env("TEST_EXCHANGE_API_KEY")
        System.delete_env("TEST_EXCHANGE_API_SECRET")
        System.delete_env("TEST_EXCHANGE_PASSPHRASE")
      end)

      assert :ok = CCXT.Testnet.register_from_env(:test_exchange, passphrase: true)

      creds = CCXT.Testnet.creds(:test_exchange)
      assert creds.api_key == "key123"
      assert creds.secret == "secret456"
      assert creds.password == "mypass"
    end

    test "registers with custom secret_suffix" do
      System.put_env("DERIBIT_TESTNET_API_KEY", "deribit_key")
      System.put_env("DERIBIT_TESTNET_SECRET_KEY", "deribit_secret")

      on_exit(fn ->
        System.delete_env("DERIBIT_TESTNET_API_KEY")
        System.delete_env("DERIBIT_TESTNET_SECRET_KEY")
      end)

      assert :ok = CCXT.Testnet.register_from_env(:deribit, testnet: true, secret_suffix: "SECRET_KEY")

      creds = CCXT.Testnet.creds(:deribit)
      assert creds.api_key == "deribit_key"
      assert creds.secret == "deribit_secret"
    end

    test "returns :skipped when env vars missing" do
      assert :skipped = CCXT.Testnet.register_from_env(:nonexistent_exchange, testnet: true)
      assert CCXT.Testnet.creds(:nonexistent_exchange) == nil
    end

    test "returns :skipped when only api_key is set" do
      System.put_env("PARTIAL_EXCHANGE_API_KEY", "key_only")

      on_exit(fn ->
        System.delete_env("PARTIAL_EXCHANGE_API_KEY")
      end)

      assert :skipped = CCXT.Testnet.register_from_env(:partial_exchange)
      assert CCXT.Testnet.creds(:partial_exchange) == nil
    end
  end

  describe "creds/1" do
    test "returns nil for unregistered exchange" do
      assert CCXT.Testnet.creds(:unknown) == nil
    end

    test "returns credentials for registered exchange" do
      CCXT.Testnet.register(:binance, api_key: "k", secret: "s")

      creds = CCXT.Testnet.creds(:binance)
      assert %CCXT.Credentials{} = creds
      assert creds.api_key == "k"
    end
  end

  describe "creds!/1" do
    test "raises for unregistered exchange" do
      assert_raise ArgumentError, ~r/No credentials registered for unknown/, fn ->
        CCXT.Testnet.creds!(:unknown)
      end
    end

    test "returns credentials for registered exchange" do
      CCXT.Testnet.register(:kraken, api_key: "k", secret: "s")

      creds = CCXT.Testnet.creds!(:kraken)
      assert %CCXT.Credentials{} = creds
    end
  end

  describe "registered?/1" do
    test "returns false for unregistered exchange" do
      refute CCXT.Testnet.registered?(:unknown)
    end

    test "returns true for registered exchange" do
      CCXT.Testnet.register(:gate, api_key: "k", secret: "s")

      assert CCXT.Testnet.registered?(:gate)
    end
  end

  describe "registered_exchanges/0" do
    test "returns empty list when no exchanges registered" do
      assert CCXT.Testnet.registered_exchanges() == []
    end

    test "lists all registered exchanges with sandbox keys" do
      CCXT.Testnet.register(:bybit, api_key: "k", secret: "s")
      CCXT.Testnet.register(:binance, api_key: "k", secret: "s")
      CCXT.Testnet.register(:okx, api_key: "k", secret: "s")

      exchanges = CCXT.Testnet.registered_exchanges()
      assert length(exchanges) == 3
      assert {:bybit, :default} in exchanges
      assert {:binance, :default} in exchanges
      assert {:okx, :default} in exchanges
    end
  end

  describe "clear/0" do
    test "removes all registered credentials" do
      CCXT.Testnet.register(:bybit, api_key: "k", secret: "s")
      CCXT.Testnet.register(:binance, api_key: "k", secret: "s")

      assert length(CCXT.Testnet.registered_exchanges()) == 2

      CCXT.Testnet.clear()

      assert CCXT.Testnet.registered_exchanges() == []
      assert CCXT.Testnet.creds(:bybit) == nil
      assert CCXT.Testnet.creds(:binance) == nil
    end
  end

  describe "register_all_from_env/1" do
    test "registers multiple exchanges and returns successfully registered ones" do
      System.put_env("EXCHANGE_A_API_KEY", "key_a")
      System.put_env("EXCHANGE_A_API_SECRET", "secret_a")
      System.put_env("EXCHANGE_B_API_KEY", "key_b")
      System.put_env("EXCHANGE_B_API_SECRET", "secret_b")
      # exchange_c not set - should be skipped

      on_exit(fn ->
        System.delete_env("EXCHANGE_A_API_KEY")
        System.delete_env("EXCHANGE_A_API_SECRET")
        System.delete_env("EXCHANGE_B_API_KEY")
        System.delete_env("EXCHANGE_B_API_SECRET")
      end)

      configs = [
        {:exchange_a, []},
        {:exchange_b, []},
        {:exchange_c, []}
      ]

      registered = CCXT.Testnet.register_all_from_env(configs)

      assert length(registered) == 2
      assert {:exchange_a, :default} in registered
      assert {:exchange_b, :default} in registered
      refute {:exchange_c, :default} in registered

      # Verify credentials are actually registered
      assert CCXT.Testnet.creds(:exchange_a).api_key == "key_a"
      assert CCXT.Testnet.creds(:exchange_b).api_key == "key_b"
      assert CCXT.Testnet.creds(:exchange_c) == nil
    end

    test "returns empty list when no credentials are available" do
      configs = [
        {:nonexistent_a, testnet: true},
        {:nonexistent_b, testnet: true}
      ]

      registered = CCXT.Testnet.register_all_from_env(configs)

      assert registered == []
    end

    test "handles empty config list" do
      registered = CCXT.Testnet.register_all_from_env([])

      assert registered == []
    end
  end
end
