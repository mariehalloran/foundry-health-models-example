FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ClinicalTrialChat.Probe.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish --configuration Release --output /app/publish \
    --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/runtime:10.0 AS final
WORKDIR /app

COPY --from=build /app/publish .
USER $APP_UID

ENTRYPOINT ["dotnet", "ClinicalTrialChat.Probe.dll"]
