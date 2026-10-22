defmodule Kewkew.Accounts.User do
  @moduledoc "A staff identity authenticated with AshAuthentication."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    tokens do
      enabled? true
      token_resource Kewkew.Accounts.Token
      signing_secret Kewkew.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider
        registration_enabled? false
      end
    end
  end

  postgres do
    table "users"
    repo Kewkew.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in an authentication token."
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :sign_in_with_password do
      description "Authenticate a staff user with email and password."
      get? true

      argument :email, :ci_string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      description "Exchange a short-lived sign-in token for an authentication token."
      get? true

      argument :token, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        allow_nil? false
      end
    end

    update :change_password do
      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 12]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    create :provision_staff_user do
      description "Creates a staff login for a trusted administrator workflow."
      accept []

      argument :email, :ci_string, allow_nil?: false

      argument :password, :string,
        allow_nil?: false,
        sensitive?: true,
        constraints: [min_length: 12]

      change set_attribute(:email, arg(:email))
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
