using AddressApp.Options;
using AddressApp.Services;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<AddressAutocompleteOptions>(
    builder.Configuration.GetSection(AddressAutocompleteOptions.SectionName));

builder.Services.AddSingleton<IAddressStore, InMemoryAddressStore>();
builder.Services.AddControllersWithViews();

var app = builder.Build();

var autocomplete = app.Services.GetRequiredService<IOptions<AddressAutocompleteOptions>>().Value;
if (autocomplete.Enabled && string.IsNullOrWhiteSpace(autocomplete.GoogleMapsApiKey))
{
    app.Logger.LogWarning(
        "AddressAutocomplete is enabled but no GoogleMapsApiKey is configured; the feature stays off. " +
        "Set it with: dotnet user-secrets set \"AddressAutocomplete:GoogleMapsApiKey\" \"<your key>\"");
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Address/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

// Maps both the MVC route below and the attribute-routed Web API (api/addresses).
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Address}/{action=Index}/{id?}");

app.Run();
