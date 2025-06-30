using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using System.Collections;

namespace Weather.API.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class AzureKeyVaultSecretsController : ControllerBase
    {
        [HttpGet(Name = "GetSecretsAndCerts")]
        public IDictionary Get()
        {
            var environments = Environment.GetEnvironmentVariables();
            return environments;
        }
    }
}
